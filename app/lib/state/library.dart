import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../models.dart';
import 'progress_store.dart';
import 'session.dart';

enum SortMode { recent, title, author, added, length }

/// Books, listening progress and syncing for the logged-in user.
class Library extends ChangeNotifier {
  final Session session;
  Library(this.session) {
    _net = Connectivity().onConnectivityChanged.listen(_onNetwork);
  }
  StreamSubscription<List<ConnectivityResult>>? _net;

  List<Book> books = [];
  Map<String, Book> byId = {};
  Map<String, Progress> progress = {};
  bool loading = false;
  String? error;
  bool offline = false;
  DateTime? _lastFailure;

  /// Called after the book list was loaded from the server (used to store covers).
  void Function(List<Book> books)? onRefreshed;
  DateTime? lastSync;

  ProgressStore? _store;
  String? _storeKey;
  String? _etag;
  Timer? _syncTimer;
  bool _syncing = false;

  /// Called by the player whenever another device's newer position arrives.
  void Function(Set<String> changed)? onRemoteProgress;

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/library_${session.userKey}.json');
  }

  Future<void> open() async {
    if (!session.loggedIn) return;
    if (_storeKey != session.userKey) {
      await _store?.close();
      _store = await ProgressStore.open(session.userKey);
      _storeKey = session.userKey;
    }
    progress = await _store!.all();
    // Show the cached library immediately, then refresh in the background.
    try {
      final f = await _cacheFile();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _etag = raw['etag'] as String?;
        _setBooks(raw['body'] as String);
      }
    } catch (_) {}
    try {
      final net = await Connectivity().checkConnectivity();
      if (net.every((c) => c == ConnectivityResult.none)) offline = true;
    } catch (_) {}
    notifyListeners();
    refresh();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  /// Airplane mode or lost Wi-Fi shows up at once, not only after the next failed request.
  void _onNetwork(List<ConnectivityResult> r) {
    if (r.every((c) => c == ConnectivityResult.none)) {
      if (!offline) {
        offline = true;
        _lastFailure = DateTime.now();
        notifyListeners();
      }
    } else if (offline && session.loggedIn) {
      refresh(); // clears [offline] once the server answers
    }
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }

  void close() {
    _syncTimer?.cancel();
    books = [];
    byId = {};
    progress = {};
    _etag = null;
    notifyListeners();
  }

  void _setBooks(String body) {
    final d = jsonDecode(body) as Map<String, dynamic>;
    books = (d['books'] as List).map((e) => Book.fromJson(e)).toList();
    byId = {for (final b in books) b.id: b};
  }

  Future<void> refresh() async {
    if (!session.loggedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await session.api.library(books.isEmpty ? null : _etag);
      if (res != null) {
        _etag = res.$1;
        _setBooks(res.$2);
        final f = await _cacheFile();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({'etag': _etag, 'body': res.$2}));
        await tmp.rename(f.path);
      }
      offline = false;
      onRefreshed?.call(books);
      await sync();
    } on ApiException catch (e) {
      if (e.unauthorized) {
        session.markAuthExpired();
      } else {
        offline = true;
        _lastFailure = DateTime.now();
        error = e.message;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Push local changes, then pull everything newer from the server.
  Future<Set<String>> sync() async {
    if (_store == null || !session.loggedIn || session.authExpired || _syncing) return {};
    _syncing = true;
    final changed = <String>{};
    try {
      final dirty = await _store!.dirty();
      if (dirty.isNotEmpty) {
        changed.addAll(await _store!.applyRemote(await session.api.pushProgress(dirty), fromPush: true));
      }
      changed.addAll(await _store!.applyRemote(await session.api.progress()));
      progress = await _store!.all();
      offline = false;
      lastSync = DateTime.now();
      if (changed.isNotEmpty) onRemoteProgress?.call(changed);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.unauthorized) {
        session.markAuthExpired();
      } else {
        offline = true;
        _lastFailure = DateTime.now();
      }
    } catch (_) {
      offline = true;
      _lastFailure = DateTime.now();
    } finally {
      _syncing = false;
    }
    return changed;
  }

  /// Fetches only this book's server progress before playback starts, so a
  /// position from another device is never missed. Times out quickly offline.
  Future<void> pullBeforePlay() async {
    if (session.authExpired) return;
    // No network at all, or the server failed moments ago: play right away.
    try {
      final net = await Connectivity().checkConnectivity();
      if (net.every((c) => c == ConnectivityResult.none)) return;
    } catch (_) {}
    if (offline && _lastFailure != null && DateTime.now().difference(_lastFailure!).inSeconds < 60) return;
    try {
      await sync().timeout(const Duration(seconds: 4));
    } catch (_) {}
  }


  Future<void> savePosition(String bookId, double position, {bool? finished, bool push = false}) async {
    final store = _store;
    if (store == null) return;
    final cur = progress[bookId];
    final pr = Progress(bookId, position, finished ?? cur?.finished ?? false,
        DateTime.now().millisecondsSinceEpoch, Session.deviceName);
    progress[bookId] = pr;
    await store.saveLocal(pr);
    notifyListeners();
    if (push) unawaited(sync());
  }

  Future<void> markFinished(String bookId, bool finished) async {
    final b = byId[bookId];
    await savePosition(bookId, finished ? (b?.duration ?? 0) : 0, finished: finished, push: true);
  }

  Future<void> resetProgress(String bookId) async {
    await savePosition(bookId, 0, finished: false, push: true);
  }

  // ------------------------------------------------------------ queries

  double positionOf(String id) => progress[id]?.position ?? 0;
  bool isFinished(String id) => progress[id]?.finished ?? false;
  bool isStarted(String id) {
    final p = progress[id];
    return p != null && !p.finished && p.position > 5;
  }

  /// Finished for cleaning up: marked finished, or only the tail is left.
  /// Books often end with credits, ads or previews, so the last 2 % count as
  /// done, at least 10 and at most 30 minutes.
  bool isPracticallyFinished(Book b) {
    if (isFinished(b.id)) return true;
    final p = progress[b.id];
    if (p == null || p.position <= 0) return false;
    final tolerance = (b.duration * 0.02).clamp(600.0, 1800.0);
    return b.duration - p.position <= tolerance;
  }

  double fractionOf(Book b) => b.duration <= 0 ? 0 : (positionOf(b.id) / b.duration).clamp(0, 1);

  List<Book> get inProgress {
    final list = books.where((b) => isStarted(b.id)).toList();
    list.sort((a, b) => progress[b.id]!.updatedAt.compareTo(progress[a.id]!.updatedAt));
    return list;
  }

  Book? get lastPlayed => inProgress.isEmpty ? null : inProgress.first;

  List<Book> get recentlyAdded {
    final list = [...books]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list.take(20).toList();
  }

  /// Next unstarted part of every series where the user finished the previous part.
  List<Book> get upNextInSeries {
    final out = <Book>[];
    for (final entry in series.entries) {
      final list = entry.value;
      if (list.any((b) => isStarted(b.id))) continue;
      final lastDone = list.lastIndexWhere((b) => isFinished(b.id));
      if (lastDone >= 0 && lastDone + 1 < list.length) {
        final next = list[lastDone + 1];
        if (!isFinished(next.id)) out.add(next);
      }
    }
    return out;
  }

  Map<String, List<Book>> get series {
    final m = <String, List<Book>>{};
    for (final b in books) {
      final s = b.seriesName;
      if (s == null || s.isEmpty) continue;
      m.putIfAbsent(s, () => []).add(b);
    }
    for (final l in m.values) {
      l.sort((a, b) => a.seriesIndex.compareTo(b.seriesIndex));
    }
    return m;
  }

  Map<String, List<Book>> get authors {
    final m = <String, List<Book>>{};
    for (final b in books) {
      m.putIfAbsent(b.author, () => []).add(b);
    }
    for (final l in m.values) {
      l.sort((a, b) {
        final s = (a.seriesName ?? '').compareTo(b.seriesName ?? '');
        if (s != 0) return s;
        final i = a.seriesIndex.compareTo(b.seriesIndex);
        return i != 0 ? i : a.title.compareTo(b.title);
      });
    }
    return m;
  }

  List<Book> sorted(List<Book> input, SortMode mode) {
    final list = [...input];
    int byTitle(Book a, Book b) => _key(a.title).compareTo(_key(b.title));
    switch (mode) {
      case SortMode.title:
        list.sort(byTitle);
      case SortMode.author:
        list.sort((a, b) {
          final c = _key(a.author).compareTo(_key(b.author));
          if (c != 0) return c;
          final s = (a.seriesName ?? a.title).compareTo(b.seriesName ?? b.title);
          return s != 0 ? s : a.seriesIndex.compareTo(b.seriesIndex);
        });
      case SortMode.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case SortMode.length:
        list.sort((a, b) => b.duration.compareTo(a.duration));
      case SortMode.recent:
        list.sort((a, b) {
          final pa = progress[a.id]?.updatedAt ?? 0;
          final pb = progress[b.id]?.updatedAt ?? 0;
          return pa != pb ? pb.compareTo(pa) : byTitle(a, b);
        });
    }
    return list;
  }

  static String _key(String s) => s
      .toLowerCase()
      .replaceFirst(RegExp(r'^(the|der|die|das|a|an|ein|eine)\s+'), '')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u');

  List<Book> search(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return books;
    return books.where((b) {
      return b.title.toLowerCase().contains(t) ||
          b.author.toLowerCase().contains(t) ||
          (b.narrator?.toLowerCase().contains(t) ?? false) ||
          (b.series?.toLowerCase().contains(t) ?? false) ||
          (b.genre?.toLowerCase().contains(t) ?? false);
    }).toList();
  }
}

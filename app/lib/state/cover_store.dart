import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'session.dart';

/// Keeps book covers on the device permanently (not in a purgeable cache),
/// so the library looks complete offline.
///
/// Small covers for every book are fetched in the background after the
/// library loads; large covers are fetched for books that get downloaded.
class CoverStore extends ChangeNotifier {
  final Session session;
  CoverStore(this.session);

  late Directory _dir;
  final Set<String> _have = {}; // file names present on disk
  final Set<String> _inFlight = {};
  bool _prefetching = false;

  Future<void> init() async {
    _dir = Directory('${(await getApplicationSupportDirectory()).path}/covers');
    await _dir.create(recursive: true);
    await for (final f in _dir.list()) {
      if (f is File && f.path.endsWith('.jpg')) _have.add(f.uri.pathSegments.last);
    }
  }

  String _name(String bookId, bool full) => '${bookId}_${full ? 'f' : 't'}.jpg';

  /// Local file for the best available cover, or null.
  File? file(String bookId, {bool full = false}) {
    if (full && _have.contains(_name(bookId, true))) return File('${_dir.path}/${_name(bookId, true)}');
    if (_have.contains(_name(bookId, false))) return File('${_dir.path}/${_name(bookId, false)}');
    return null;
  }

  bool hasExact(String bookId, {bool full = false}) => _have.contains(_name(bookId, full));

  Future<bool> fetch(String bookId, {bool full = false}) async {
    final name = _name(bookId, full);
    if (_have.contains(name)) return true;
    // Already being fetched (e.g. by a visible cover): not a failure.
    if (_inFlight.contains(name)) return true;
    if (!session.loggedIn) return false;
    _inFlight.add(name);
    try {
      final api = session.api;
      final res = await http
          .get(Uri.parse(api.coverUrl(bookId, full: full)), headers: api.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
      final tmp = File('${_dir.path}/$name.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      await tmp.rename('${_dir.path}/$name');
      _have.add(name);
      return true;
    } catch (_) {
      return false;
    } finally {
      _inFlight.remove(name);
    }
  }

  /// Fetch every missing small cover, four at a time. Stops quietly when offline.
  Future<void> prefetch(Iterable<Book> books) async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      final todo = books.where((b) => b.hasCover && !_have.contains(_name(b.id, false))).toList();
      var failures = 0;
      var changed = 0;
      for (var i = 0; i < todo.length; i += 4) {
        final batch = todo.skip(i).take(4);
        final results = await Future.wait(batch.map((b) => fetch(b.id)));
        for (final ok in results) {
          ok ? changed++ : failures++;
        }
        if (failures >= 8 && changed == 0) break; // server unreachable, try again later
        if (changed >= 40) {
          changed = 0;
          notifyListeners();
        }
      }
      notifyListeners();
    } finally {
      _prefetching = false;
    }
  }

  int get count => _have.length;
}

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'session.dart';

enum DlState { none, queued, downloading, paused, failed, done }

class BookDownload {
  final DlState state;
  final double progress; // 0..1 over all files of the book
  final String? error;
  const BookDownload(this.state, this.progress, [this.error]);
  static const none = BookDownload(DlState.none, 0);
}

/// Keeps books on the device.
///
/// A book the user played or asked for is "wanted". Wanted books are retried
/// until every file is complete: the downloader retries on its own, and a
/// watchdog re-queues anything that ended in failure or got lost when the OS
/// killed the app.
class Downloads extends ChangeNotifier {
  final Session session;
  Downloads(this.session);

  static const _group = 'books';
  late String _root;
  final Set<String> _wanted = {};
  final Map<String, Book> _books = {};
  final Map<String, TaskStatus> _status = {}; // taskId -> status
  final Map<String, double> _fileProgress = {}; // taskId -> 0..1
  final Map<String, String> _errors = {};
  final Map<String, bool> _completeCache = {};
  final Map<String, DateTime> _lastActivity = {}; // taskId -> last status/progress event
  static const _stallAfter = Duration(minutes: 3);
  Timer? _watchdog;

  /// Called whenever a book is queued (used to store its large cover).
  void Function(Book book)? onEnsure;

  /// Player hook: a file finished downloading (bookId, file index).
  void Function(String bookId, int index)? onFileComplete;

  /// Called before a book's files are deleted (the player lets go of it).
  Future<void> Function(Book book)? onRemoved;

  /// Large files only over Wi-Fi (default). Playing still works on mobile data:
  /// the book streams and downloads once Wi-Fi is back.
  bool wifiOnly = true;
  bool _onWifi = true;
  StreamSubscription<List<ConnectivityResult>>? _net;

  /// Downloads are held back right now because there is no Wi-Fi.
  bool get waitingForWifi => wifiOnly && !_onWifi;

  Future<void> setWifiOnly(bool on) async {
    wifiOnly = on;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('wifi_only', on);
    await FileDownloader().requireWiFi(on ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks, rescheduleRunningTasks: true);
    if (!on) unawaited(resumeWanted());
  }

  void _onNetwork(List<ConnectivityResult> r) {
    final wifi = r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    if (wifi == _onWifi) return;
    _onWifi = wifi;
    // Coming back to Wi-Fi: give waiting tasks a fresh grace period before the
    // stall watchdog looks at them again.
    final now = DateTime.now();
    for (final k in _lastActivity.keys.toList()) {
      _lastActivity[k] = now;
    }
    notifyListeners();
  }

  Future<void> init() async {
    _root = '${(await getApplicationSupportDirectory()).path}/books';
    await Directory(_root).create(recursive: true);
    final p = await SharedPreferences.getInstance();
    _wanted.addAll(p.getStringList('wanted_downloads') ?? []);
    wifiOnly = p.getBool('wifi_only') ?? true;
    try {
      _onNetwork(await Connectivity().checkConnectivity());
    } catch (_) {}
    _net = Connectivity().onConnectivityChanged.listen(_onNetwork);

    FileDownloader().configure(androidConfig: [(Config.runInForeground, Config.always)]);
    FileDownloader().configureNotification(
      running: const TaskNotification('{displayName}', 'Wird geladen · {progress}'),
      error: const TaskNotification('{displayName}', 'Download unterbrochen, wird wiederholt'),
      progressBar: true,
    );
    FileDownloader().updates.listen(_onUpdate);
    await FileDownloader().start(autoCleanDatabase: true);
    await FileDownloader().requireWiFi(wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks, rescheduleRunningTasks: false);
    for (final r in await FileDownloader().database.allRecords(group: _group)) {
      _status[r.taskId] = r.status;
      _fileProgress[r.taskId] = r.progress.clamp(0, 1);
      _lastActivity[r.taskId] = DateTime.now(); // give resumed tasks a fresh grace period
    }
    _watchdog = Timer.periodic(const Duration(seconds: 45), (_) => resumeWanted());
    notifyListeners();
  }

  bool _askedNotifications = false;

  /// Android 13+: without this permission there is no player in the
  /// notification shade or on the lock screen. Asked once per app start at most.
  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid || _askedNotifications) return;
    _askedNotifications = true;
    try {
      final st = await FileDownloader().permissions.status(PermissionType.notifications);
      if (st != PermissionStatus.granted) {
        await FileDownloader().permissions.request(PermissionType.notifications);
      }
    } catch (e) {
      debugPrint('[downloads] notification permission: $e');
    }
  }

  void registerBooks(Iterable<Book> books) {
    for (final b in books) {
      _books[b.id] = b;
    }
    resumeWanted();
  }

  String _taskId(String bookId, int index) => '${bookId}_$index';
  String bookDir(String bookId) => '$_root/$bookId';
  String localPath(Book b, AudioFileInfo f) => '${bookDir(b.id)}/${f.index}.${f.ext}';

  bool fileComplete(Book b, AudioFileInfo f) {
    final key = _taskId(b.id, f.index);
    final cached = _completeCache[key];
    if (cached == true) return true;
    final file = File(localPath(b, f));
    final ok = file.existsSync() && file.lengthSync() == f.size;
    if (ok) _completeCache[key] = true;
    return ok;
  }

  bool isComplete(Book b) => b.files.every((f) => fileComplete(b, f));
  bool isWanted(String bookId) => _wanted.contains(bookId);

  BookDownload stateOf(Book b) {
    if (isComplete(b)) return const BookDownload(DlState.done, 1);
    if (!_wanted.contains(b.id)) {
      // Paused by the user: started files count as a paused download, not as "never loaded".
      final started = b.files.any((f) =>
          fileComplete(b, f) ||
          _status[_taskId(b.id, f.index)] == TaskStatus.paused ||
          (_fileProgress[_taskId(b.id, f.index)] ?? 0) > 0);
      return started ? BookDownload(DlState.paused, _bookProgress(b)) : BookDownload.none;
    }
    final statuses = b.files.where((f) => !fileComplete(b, f)).map((f) => _status[_taskId(b.id, f.index)]);
    final prog = _bookProgress(b);
    if (statuses.any((s) => s == TaskStatus.running)) return BookDownload(DlState.downloading, prog);
    if (statuses.any((s) => s == TaskStatus.failed || s == TaskStatus.notFound)) {
      final err = b.files.map((f) => _errors[_taskId(b.id, f.index)]).whereType<String>().firstOrNull;
      return BookDownload(DlState.failed, prog, err);
    }
    if (statuses.any((s) => s == TaskStatus.paused)) return BookDownload(DlState.paused, prog);
    return BookDownload(DlState.queued, prog);
  }

  double _bookProgress(Book b) {
    final total = b.totalSize;
    if (total == 0) return 0;
    var done = 0.0;
    for (final f in b.files) {
      done += fileComplete(b, f) ? f.size : f.size * (_fileProgress[_taskId(b.id, f.index)] ?? 0);
    }
    return (done / total).clamp(0, 1);
  }

  int get usedBytes {
    var sum = 0;
    for (final b in _books.values) {
      for (final f in b.files) {
        if (fileComplete(b, f)) sum += f.size;
      }
    }
    return sum;
  }

  List<Book> get downloadedOrWanted {
    final ids = {..._wanted};
    for (final b in _books.values) {
      if (b.files.any((f) => fileComplete(b, f))) ids.add(b.id);
    }
    return ids.map((i) => _books[i]).whereType<Book>().toList();
  }

  Future<void> _saveWanted() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('wanted_downloads', _wanted.toList());
  }

  /// Queue every missing file of [b]. Safe to call repeatedly.
  Future<void> ensure(Book b) async {
    _books[b.id] = b;
    onEnsure?.call(b);
    if (_wanted.add(b.id)) await _saveWanted();
    await Directory(bookDir(b.id)).create(recursive: true);
    final api = session.api;
    for (final f in b.files) {
      if (fileComplete(b, f)) continue;
      final id = _taskId(b.id, f.index);
      final st = _status[id];
      if (st == TaskStatus.running || st == TaskStatus.enqueued || st == TaskStatus.waitingToRetry) continue;
      if (st == TaskStatus.paused) {
        final task = await FileDownloader().taskForId(id);
        if (task is DownloadTask && await FileDownloader().resume(task)) continue;
      }
      final task = DownloadTask(
        taskId: id,
        url: api.fileUrl(b.id, f),
        headers: api.authHeaders,
        filename: '${f.index}.${f.ext}',
        directory: 'books/${b.id}',
        baseDirectory: BaseDirectory.applicationSupport,
        group: _group,
        updates: Updates.statusAndProgress,
        retries: 10,
        allowPause: true,
        displayName: b.title,
        metaData: b.id,
      );
      debugPrint('[downloads] enqueue $id (previous: $st)');
      _status[id] = TaskStatus.enqueued;
      _lastActivity[id] = DateTime.now();
      _errors.remove(id);
      if (!await FileDownloader().enqueue(task)) {
        // An old task with this id is still known to the OS: drop it and start fresh.
        await FileDownloader().cancelTaskWithId(id);
        await FileDownloader().database.deleteRecordWithId(id);
        if (!await FileDownloader().enqueue(task)) {
          _status[id] = TaskStatus.failed;
          _errors[id] = 'Download konnte nicht gestartet werden, wird erneut versucht';
        }
      }
    }
    notifyListeners();
  }

  /// Re-queue wanted books that are incomplete and not actively downloading.
  /// A task that has shown no sign of life for a few minutes counts as stuck:
  /// it is cancelled and started again.
  Future<void> resumeWanted() async {
    if (!session.loggedIn || session.authExpired) return;
    // Waiting for Wi-Fi is not a stall: leave the queued tasks alone.
    if (waitingForWifi) return;
    final now = DateTime.now();
    for (final id in _wanted.toList()) {
      final b = _books[id];
      if (b == null || isComplete(b)) continue;
      for (final f in b.files.where((f) => !fileComplete(b, f))) {
        final tid = _taskId(b.id, f.index);
        final st = _status[tid];
        final last = _lastActivity[tid];
        final active = st == TaskStatus.enqueued || st == TaskStatus.running || st == TaskStatus.waitingToRetry;
        if (active && (last == null || now.difference(last) > _stallAfter)) {
          debugPrint('[downloads] $tid stalled ($st), restarting');
          await FileDownloader().cancelTaskWithId(tid);
          await FileDownloader().database.deleteRecordWithId(tid);
          _status.remove(tid);
          _lastActivity.remove(tid);
        }
      }
      final stuck = b.files.where((f) => !fileComplete(b, f)).any((f) {
        final st = _status[_taskId(b.id, f.index)];
        return st == null ||
            st == TaskStatus.failed ||
            st == TaskStatus.canceled ||
            st == TaskStatus.complete || // marked complete but file missing or truncated
            st == TaskStatus.paused;
      });
      if (stuck) await ensure(b);
    }
  }

  Future<void> pause(Book b) async {
    for (final f in b.files) {
      final task = await FileDownloader().taskForId(_taskId(b.id, f.index));
      if (task is DownloadTask) await FileDownloader().pause(task);
    }
    _wanted.remove(b.id);
    await _saveWanted();
    notifyListeners();
  }

  Future<void> remove(Book b) async {
    await onRemoved?.call(b);
    _wanted.remove(b.id);
    await _saveWanted();
    await FileDownloader().cancelTasksWithIds(b.files.map((f) => _taskId(b.id, f.index)));
    for (final f in b.files) {
      final id = _taskId(b.id, f.index);
      _status.remove(id);
      _fileProgress.remove(id);
      _completeCache.remove(id);
      await FileDownloader().database.deleteRecordWithId(id);
    }
    final dir = Directory(bookDir(b.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  void _onUpdate(TaskUpdate u) {
    final id = u.task.taskId;
    _lastActivity[id] = DateTime.now();
    if (u is TaskStatusUpdate) {
      debugPrint('[downloads] $id -> ${u.status}');
      _status[id] = u.status;
      if (u.status == TaskStatus.complete) {
        _fileProgress[id] = 1;
        _completeCache.remove(id);
        final bookId = u.task.metaData;
        final idx = int.tryParse(id.split('_').last);
        final b = _books[bookId];
        if (b != null && idx != null && idx < b.files.length && fileComplete(b, b.files[idx])) {
          onFileComplete?.call(bookId, idx);
        }
      } else if (u.status == TaskStatus.failed || u.status == TaskStatus.notFound) {
        _errors[id] = u.exception?.description ?? 'Download fehlgeschlagen';
      }
    } else if (u is TaskProgressUpdate) {
      if (u.progress >= 0 && u.progress <= 1) _fileProgress[id] = u.progress;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _net?.cancel();
    super.dispose();
  }
}

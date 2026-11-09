import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'downloads.dart';
import 'library.dart';

enum SleepMode { off, timer, endOfChapter }

/// One player for the whole app. Works in global book time (seconds from the
/// start of the book) and maps that onto the book's files.
///
/// It also is the audio_service handler, so lock screen, notification,
/// headset and car controls all go through the same code.
class PlayerController extends BaseAudioHandler with SeekHandler, ChangeNotifier {
  final Library library;
  final Downloads downloads;
  final AudioPlayer player = AudioPlayer();

  PlayerController(this.library, this.downloads) {
    player.playbackEventStream.listen(_broadcast, onError: (Object e, StackTrace st) {
      debugPrint('[player] source error: $e');
      if (_canRecover) {
        _recover();
      } else {
        _intendPlay = false;
        lastError = library.offline
            ? 'Verbindung verloren. Dieser Teil des Buchs ist noch nicht geladen.'
            : 'Wiedergabe fehlgeschlagen. Ist der Server erreichbar?';
        notifyListeners();
      }
    });
    player.playingStream.listen((playing) {
      if (!playing) _onPaused();
      // Android only shows the player (notification, lock screen) and keeps
      // playing in the background once it learns playback started.
      _broadcast(player.playbackEvent);
      notifyListeners();
    });
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onBookEnd();
      if (s == ProcessingState.ready && _recovering) {
        _recovering = false;
        _retries = 0;
        _retryTimer?.cancel();
      }
      _watchStall(s);
      _broadcast(player.playbackEvent);
      notifyListeners();
    });
    player.positionStream.listen((_) {
      if (_loaded && !_loading && !_recovering) _lastPos = position;
      _tick();
    });
    downloads.onFileComplete = _onFileComplete;
    downloads.onRemoved = _onRemoved;
    library.onRemoteProgress = _onRemoteProgress;
    _loadPrefs();
  }

  Book? book;
  /// True once the book's audio sources are set on the player. Not tied to
  /// ProcessingState, which can briefly read idle right after loading on iOS.
  bool _loaded = false;
  /// playBook is preparing (sync, position lookup, first load).
  bool _starting = false;
  /// Number of source loads in flight; they can overlap (stream, then local file).
  int _loadsRunning = 0;
  int _loadGen = 0;
  bool get _loading => _starting || _loadsRunning > 0;
  String? lastError;
  double speed = 1.0;
  int skipBack = 15;
  int skipForward = 30;
  List<bool> _local = [];
  DateTime? _pausedAt;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  SleepMode sleepMode = SleepMode.off;
  DateTime? sleepUntil;
  Timer? _sleepTimer;
  bool _fading = false;
  bool _ducked = false;

  /// Turns the audiobook down while something else talks over it (the parrot
  /// easter egg), and back up afterwards. Safe to call repeatedly.
  void duck(bool on) {
    if (on == _ducked) return;
    _ducked = on;
    debugPrint('[player] duck $on');
    if (_fading) return; // the sleep timer fade owns the volume right now
    player.setVolume(on ? .25 : 1);
  }

  bool get loading => _loading || player.processingState == ProcessingState.loading;

  /// The user pressed play and is waiting for audio: buffering a stream, or
  /// retrying a jump into a part that is not downloaded yet. Shown as a spinner.
  bool get waiting =>
      _recovering ||
      (_loading && _intendPlay) ||
      (player.playing &&
          (player.processingState == ProcessingState.buffering || player.processingState == ProcessingState.loading));
  bool get buffering => player.processingState == ProcessingState.buffering;
  bool get playing => player.playing;

  static Future<void> configureSession() async {
    final s = await AudioSession.instance;
    await s.configure(const AudioSessionConfiguration.speech());
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    speed = p.getDouble('speed') ?? 1.0;
    skipBack = p.getInt('skip_back') ?? 15;
    skipForward = p.getInt('skip_forward') ?? 30;
    notifyListeners();
  }

  Future<void> setSkips(int back, int fwd) async {
    skipBack = back;
    skipForward = fwd;
    final p = await SharedPreferences.getInstance();
    await p.setInt('skip_back', back);
    await p.setInt('skip_forward', fwd);
    notifyListeners();
  }

  // ------------------------------------------------------------ position

  double get position {
    final b = book;
    if (b == null) return 0;
    if (_recovering) return _lastPos;
    if (!_loaded) return library.positionOf(b.id);
    final i = player.currentIndex ?? 0;
    return b.fileOffset(i) + player.position.inMilliseconds / 1000.0;
  }

  Stream<double> get positionStream => player.positionStream.map((_) => position);

  Chapter? get chapter {
    final b = book;
    if (b == null || b.chapters.isEmpty) return null;
    return b.chapters[b.chapterIndexAt(position)];
  }

  int get chapterIndex => book == null ? 0 : book!.chapterIndexAt(position);

  // ------------------------------------------------------------ availability

  /// Where [b] would start playing.
  double startPosition(Book b) {
    if (book?.id == b.id && _loaded) return position;
    return library.isFinished(b.id) ? 0 : library.positionOf(b.id);
  }

  /// True when the part of [b] at [pos] is stored on this device.
  bool isLocalAt(Book b, double pos) {
    if (b.files.isEmpty) return false;
    final (i, _) = b.locate(pos.clamp(0, b.duration));
    return downloads.fileComplete(b, b.files[i]);
  }

  /// Offline and the part to play is not on the device: playing cannot work.
  bool unavailable(Book b, [double? at]) => library.offline && !isLocalAt(b, at ?? startPosition(b));

  String _offlineMessage(Book b) => downloads.isWanted(b.id)
      ? 'Du bist offline. „${b.title}“ lädt weiter, sobald du wieder online bist.'
      : 'Du bist offline. „${b.title}“ ist noch nicht auf diesem Gerät.';

  /// A stream that keeps buffering (connection lost mid-book) is stopped with a
  /// clear message instead of showing "playing" forever.
  Timer? _stallTimer;
  void _watchStall(ProcessingState s) {
    final b = book;
    final streaming = b != null && _loaded && !_isCurrentLocal;
    if ((s == ProcessingState.buffering || s == ProcessingState.loading) && player.playing && streaming) {
      _stallTimer ??= Timer(Duration(seconds: library.offline ? 3 : 20), () {
        _stallTimer = null;
        final st = player.processingState;
        if (player.playing && (st == ProcessingState.buffering || st == ProcessingState.loading)) {
          if (_canRecover) {
            _recover(); // reconnect the stream, keep waiting
          } else {
            _halt();
            lastError = 'Verbindung verloren. Dieser Teil des Buchs ist noch nicht geladen.';
            notifyListeners();
          }
        }
      });
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
  }

  // ------------------------------------------------------------ recovery

  /// Play was pressed and not paused since.
  bool _intendPlay = false;
  bool _recovering = false;
  double _lastPos = 0;
  int _retries = 0;
  Timer? _retryTimer;

  bool get _canRecover => book != null && _intendPlay && !library.offline && !_isCurrentLocal;

  /// A stream that failed or stalled (often after jumping far ahead while the
  /// book is still downloading) is reconnected at the same spot, again and
  /// again, until it plays or the file is complete (then [_onFileComplete] takes over).
  void _recover() {
    final b = book;
    if (b == null) return;
    if (!_recovering) {
      _recovering = true;
      notifyListeners();
    }
    _retryTimer?.cancel();
    final delay = Duration(seconds: (2 + _retries * 3).clamp(2, 15));
    _retries++;
    _retryTimer = Timer(delay, () async {
      if (!_recovering || book?.id != b.id) return;
      if (!_intendPlay || library.offline) {
        _recovering = false;
        if (library.offline && _intendPlay) {
          _intendPlay = false;
          lastError = 'Verbindung verloren. Dieser Teil des Buchs ist noch nicht geladen.';
        }
        notifyListeners();
        return;
      }
      debugPrint('[player] reconnect at ${_lastPos.toStringAsFixed(0)} s (try $_retries)');
      try {
        final current = await _loadWithin(b, _lastPos, const Duration(seconds: 12));
        if (current && _recovering && _intendPlay) unawaited(player.play());
      } catch (e) {
        debugPrint('[player] reconnect failed: $e');
        if (_recovering) _recover();
      }
    });
  }

  /// Pause from inside the app (sleep timer, end of book, lost connection).
  void _halt() {
    _intendPlay = false;
    _recovering = false;
    _retryTimer?.cancel();
    player.pause();
  }

  bool get _isCurrentLocal {
    final i = player.currentIndex ?? 0;
    return i < _local.length && _local[i];
  }

  // ------------------------------------------------------------ loading

  /// Show the last book in the mini player after an app start, without loading audio yet.
  void restoreLast() {
    if (book != null) return;
    final b = library.lastPlayed;
    if (b == null) return;
    book = b;
    notifyListeners();
  }

  /// Start [b]. Triggers the download right away and streams until the file is local.
  Future<void> playBook(Book b, {double? at}) async {
    lastError = null;
    if (book?.id == b.id && at == null && _loaded) {
      await play();
      return;
    }
    if (unavailable(b, at)) {
      // Do not touch the current book; remember the wish and load once online.
      unawaited(downloads.ensure(b));
      lastError = _offlineMessage(b);
      notifyListeners();
      return;
    }
    _starting = true;
    _intendPlay = true;
    unawaited(downloads.requestNotificationPermission());
    _recovering = false;
    _retryTimer?.cancel();
    _retries = 0;
    notifyListeners();
    try {
      // Only save a book that was really loaded; an idle one would overwrite newer progress from other devices.
      if (book != null && _loaded) await _save(push: true);
      unawaited(downloads.ensure(b));
      double pos;
      if (at != null) {
        pos = at;
      } else {
        await library.pullBeforePlay();
        pos = library.isFinished(b.id) ? 0 : library.positionOf(b.id);
      }
      if (unavailable(b, pos)) {
        lastError = _offlineMessage(b);
        return;
      }
      _lastPos = pos;
      try {
        await _loadWithin(b, pos, const Duration(seconds: 12));
      } catch (e) {
        // Slow answer while the book is still downloading (busy NAS or line):
        // keep waiting and retry quietly instead of showing an error.
        if (!library.offline && !isLocalAt(b, pos) && _intendPlay) {
          debugPrint('[player] start is slow, waiting: $e');
          book = b;
          _recover();
          return;
        }
        rethrow;
      }
      _starting = false;
      if (_intendPlay) await play();
    } catch (e) {
      _intendPlay = false;
      if (!downloads.isComplete(b)) {
        _loaded = false;
        unawaited(player.stop());
      }
      lastError = downloads.isComplete(b)
          ? 'Datei konnte nicht abgespielt werden.'
          : 'Buch ist noch nicht geladen und der Server ist nicht erreichbar.';
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Sets the sources. Returns false when a newer load replaced this one
  /// meanwhile (its result no longer matters, its errors are swallowed).
  Future<bool> _load(Book b, double pos) async {
    final gen = ++_loadGen;
    _loadsRunning++; // blocks position saves while sources are swapped
    try {
      await _loadInner(b, pos);
      return gen == _loadGen;
    } catch (e) {
      if (gen != _loadGen) return false;
      rethrow;
    } finally {
      _loadsRunning--;
    }
  }

  /// [_load] with a time limit. A load that runs over keeps going in the
  /// background; its late errors must not surface as unhandled.
  Future<bool> _loadWithin(Book b, double pos, Duration limit) {
    final f = _load(b, pos);
    f.ignore();
    return f.timeout(limit);
  }

  Future<void> _loadInner(Book b, double pos) async {
    book = b;
    _loaded = false;
    _local = b.files.map((f) => downloads.fileComplete(b, f)).toList();
    final api = library.session.api;
    final sources = <AudioSource>[
      for (final f in b.files)
        _local[f.index]
            ? AudioSource.file(downloads.localPath(b, f))
            // No headers: they make just_audio route through a local proxy, which
            // stalls on large files on iOS. The token is in the URL instead.
            : AudioSource.uri(Uri.parse(api.fileUrl(b.id, f))),
    ];
    final (i, off) = b.locate(pos.clamp(0, b.duration));
    await player.setSpeed(speed);
    await player.setAudioSources(sources,
        initialIndex: i, initialPosition: Duration(milliseconds: (off * 1000).round()));
    _loaded = true;
    mediaItem.add(MediaItem(
      id: b.id,
      title: b.title,
      artist: b.author,
      album: b.seriesLabel ?? b.title,
      duration: Duration(milliseconds: (b.duration * 1000).round()),
      artUri: _artUri(b),
      artHeaders: library.session.api.authHeaders,
    ));
    if (library.positionOf(b.id) != pos) {
      await library.savePosition(b.id, pos);
    }
    _broadcast(player.playbackEvent);
    notifyListeners();
  }

  /// Cover for lock screen and notification. audio_service downloads and caches
  /// it itself (the system UI cannot read files inside the app sandbox).
  Uri? _artUri(Book b) {
    if (!b.hasCover) return null;
    return Uri.parse(library.session.api.coverUrl(b.id, full: true));
  }

  void _onFileComplete(String bookId, int index) {
    final b = book;
    if (b == null || b.id != bookId) return;
    if (index < _local.length) {
      if (_local[index]) return;
      _local[index] = true;
    }
    if (_recovering || (_loaded && player.currentIndex == index)) {
      // Switch from stream to the local file at the same spot.
      final wasPlaying = player.playing || _intendPlay;
      final wasRecovering = _recovering;
      final pos = _recovering ? _lastPos : position;
      _retryTimer?.cancel();
      _retries = 0;
      debugPrint('[player] file complete, switching to local at ${pos.toStringAsFixed(0)} s');
      _switchToLocal(b, pos, wasPlaying, stopFirst: wasRecovering);
    }
  }

  /// Loads the finished local file. A stream that was still hanging is stopped
  /// first, otherwise its late failure can interrupt this load.
  Future<void> _switchToLocal(Book b, double pos, bool play, {bool stopFirst = false, int attempt = 1}) async {
    try {
      // Mark loads still in flight as replaced, so their failure does not start another reconnect.
      _loadGen++;
      if (stopFirst) await player.stop();
      final current = await _load(b, pos);
      _recovering = false;
      if (current && play && _intendPlay) unawaited(player.play());
      notifyListeners();
    } catch (e) {
      debugPrint('[player] local switch failed (try $attempt): $e');
      if (attempt < 3 && book?.id == b.id) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return _switchToLocal(b, pos, play, stopFirst: true, attempt: attempt + 1);
      }
      _recovering = false;
      _intendPlay = false;
      lastError = 'Datei konnte nicht abgespielt werden.';
      notifyListeners();
    }
  }

  void _onRemoteProgress(Set<String> changed) {
    final b = book;
    if (b == null || !changed.contains(b.id) || player.playing || _loading) return;
    final remote = library.positionOf(b.id);
    if ((remote - position).abs() > 5) seekTo(remote, save: false);
  }

  // ------------------------------------------------------------ saving

  void _tick() {
    if (book == null || !player.playing) return;
    final now = DateTime.now();
    if (now.difference(_lastSave).inSeconds >= 5) {
      _lastSave = now;
      final push = now.difference(_lastPush).inSeconds >= 30;
      if (push) _lastPush = now;
      _save(push: push);
    }
    if (sleepMode == SleepMode.endOfChapter) {
      final c = chapter;
      if (c != null && position >= c.end - 0.4) {
        _sleepNow();
      }
    }
  }

  Future<void> _save({bool push = false}) async {
    final b = book;
    if (b == null || _loading || !_loaded) return;
    final pos = position;
    final finished = pos >= b.duration - 30 ? true : null;
    await library.savePosition(b.id, pos, finished: finished ?? false, push: push);
  }

  void _onPaused() {
    if (book == null || _loading) return;
    _pausedAt = DateTime.now();
    _save(push: true);
  }

  Future<void> _onBookEnd() async {
    final b = book;
    if (b == null) return;
    _halt();
    await library.savePosition(b.id, b.duration, finished: true, push: true);
    notifyListeners();
  }

  /// Call when the app goes to the background.
  Future<void> flush() => _save(push: true);

  // ------------------------------------------------------------ transport

  @override
  Future<void> play() async {
    final b = book;
    if (b == null) return;
    if (!_loaded && !_loading) {
      // Restored after app start but never loaded: load first (exactly once).
      return playBook(b);
    }
    if (library.offline && !_isCurrentLocal) {
      unawaited(downloads.ensure(b));
      lastError = _offlineMessage(b);
      notifyListeners();
      return;
    }
    if (player.processingState == ProcessingState.completed || library.isFinished(b.id) && position >= b.duration - 1) {
      await seekTo(0);
      await library.savePosition(b.id, 0, finished: false);
    }
    final since = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
    if (since.inMinutes >= 5) {
      await seekTo(position - 10);
    } else if (since.inSeconds >= 30) {
      await seekTo(position - 3);
    }
    _pausedAt = null;
    if (_fading) {
      _fading = false;
      await player.setVolume(1);
    }
    _intendPlay = true;
    unawaited(player.play());
  }

  @override
  Future<void> pause() async {
    final wasRecovering = _recovering;
    _halt();
    if (wasRecovering) notifyListeners();
  }

  @override
  Future<void> stop() async {
    await _save(push: true);
    await player.stop();
    await super.stop();
  }

  Future<void> toggle() => (player.playing || _recovering) ? pause() : play();

  @override
  Future<void> seek(Duration position) => seekTo(position.inMilliseconds / 1000.0);

  Future<void> seekTo(double pos, {bool save = true}) async {
    final b = book;
    if (b == null) return;
    final target = pos.clamp(0.0, b.duration - 0.5).toDouble();
    final (i, off) = b.locate(target);
    _lastPos = target;
    if (_recovering) {
      // The player has no source right now; reconnect at the new spot.
      _retries = 0;
      _recover();
      if (save) await library.savePosition(b.id, target);
      notifyListeners();
      return;
    }
    await player.seek(Duration(milliseconds: (off * 1000).round()), index: i);
    if (save) await library.savePosition(b.id, target);
    _broadcast(player.playbackEvent);
    notifyListeners();
  }

  @override
  Future<void> rewind() => seekTo(position - skipBack);

  @override
  Future<void> fastForward() => seekTo(position + skipForward);

  @override
  Future<void> skipToNext() => nextChapter();

  @override
  Future<void> skipToPrevious() => previousChapter();

  Future<void> nextChapter() async {
    final b = book;
    if (b == null) return;
    final i = chapterIndex;
    if (i + 1 < b.chapters.length) await seekTo(b.chapters[i + 1].start);
  }

  Future<void> previousChapter() async {
    final b = book;
    if (b == null) return;
    final i = chapterIndex;
    final c = b.chapters[i];
    if (position - c.start > 4 || i == 0) {
      await seekTo(c.start);
    } else {
      await seekTo(b.chapters[i - 1].start);
    }
  }

  Future<void> setSpeed(double s) async {
    speed = s;
    await player.setSpeed(s);
    final p = await SharedPreferences.getInstance();
    await p.setDouble('speed', s);
    _broadcast(player.playbackEvent);
    notifyListeners();
  }

  // ------------------------------------------------------------ sleep timer

  /// Shake the phone to start the sleep timer over (Audible style). Listens to
  /// the motion sensor only while a timer runs and for a minute after it fired.
  Duration? _sleepLength;
  DateTime? _sleptAt;
  StreamSubscription<AccelerometerEvent>? _shakeSub;
  final List<DateTime> _shakePeaks = [];
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tells the UI about a shake (for a short note).
  void Function()? onShakeExtended;

  void _listenForShake(bool on) {
    if (!on) {
      _shakeSub?.cancel();
      _shakeSub = null;
      return;
    }
    // Plain accelerometer (every phone has one); gravity alone reads ~9.8.
    _shakeSub ??= accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (g < 24) return; // a real shake peaks well above 2.5 g; turning over in bed stays below
      final now = DateTime.now();
      _shakePeaks
        ..add(now)
        ..removeWhere((t) => now.difference(t) > const Duration(milliseconds: 900));
      if (_shakePeaks.length >= 3 && now.difference(_lastShake) > const Duration(seconds: 2)) {
        _lastShake = now;
        _shakePeaks.clear();
        _onShake();
      }
    }, onError: (_) {});
  }

  void _onShake() {
    final len = _sleepLength;
    if (len == null) return;
    final afterSleep = sleepMode == SleepMode.off && _sleptAt != null &&
        DateTime.now().difference(_sleptAt!) < const Duration(minutes: 1);
    if (sleepMode != SleepMode.timer && !afterSleep) return;
    debugPrint('[player] shake: sleep timer restarted');
    HapticFeedback.heavyImpact();
    setSleep(SleepMode.timer, len);
    if (afterSleep) unawaited(play());
    onShakeExtended?.call();
  }

  void setSleep(SleepMode mode, [Duration? d]) {
    _sleepTimer?.cancel();
    sleepMode = mode;
    sleepUntil = null;
    _sleptAt = null;
    if (mode == SleepMode.timer && d != null) _sleepLength = d;
    _listenForShake(mode == SleepMode.timer);
    if (_fading) {
      _fading = false;
      player.setVolume(1);
    }
    if (mode == SleepMode.timer && d != null) {
      sleepUntil = DateTime.now().add(d);
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = sleepUntil!.difference(DateTime.now());
        if (left.inSeconds <= 10 && left.inSeconds > 0 && player.playing) {
          _fading = true;
          player.setVolume((left.inMilliseconds / 10000).clamp(0.05, 1));
        }
        if (left.isNegative) _sleepNow();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Duration? get sleepLeft => sleepUntil?.difference(DateTime.now());

  Future<void> _sleepNow() async {
    _sleepTimer?.cancel();
    final wasTimer = sleepMode == SleepMode.timer;
    sleepMode = SleepMode.off;
    sleepUntil = null;
    _halt();
    // One more minute in which a shake starts the timer and the book again.
    if (wasTimer) {
      _sleptAt = DateTime.now();
      Timer(const Duration(minutes: 1), () {
        if (sleepMode == SleepMode.off) _listenForShake(false);
      });
    }
    if (_fading) {
      _fading = false;
      await player.setVolume(1);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ Android Auto
  // The car shows a small browsable library. Kept flat on purpose: a few
  // shelves, then books. Playing an item works like tapping play in the app.

  static const _shelves = [
    ('shelf:continue', 'Weiterhören'),
    ('shelf:device', 'Auf dem Gerät'),
    ('shelf:new', 'Neu in der Bibliothek'),
    ('shelf:az', 'Alle Bücher A–Z'),
  ];

  MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, displaySubtitle: subtitle, playable: false);

  MediaItem _bookItem(Book b) {
    final api = library.session.api;
    final frac = library.fractionOf(b);
    final status = library.isFinished(b.id) ? 2 : (library.isStarted(b.id) ? 1 : 0);
    return MediaItem(
      id: 'book:${b.id}',
      title: b.title,
      artist: b.author,
      album: b.seriesLabel,
      displaySubtitle: library.isStarted(b.id) ? '${b.author} · ${(frac * 100).round()} %' : b.author,
      duration: Duration(milliseconds: (b.duration * 1000).round()),
      playable: true,
      // The car's media app loads covers itself, so the token goes in the URL.
      artUri: b.hasCover ? Uri.parse('${api.coverUrl(b.id)}&token=${api.token}') : null,
      extras: {
        'android.media.extra.PLAYBACK_STATUS': status,
        if (status == 1) 'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE': frac,
      },
    );
  }

  String _letter(Book b) {
    final t = b.title.trim().toUpperCase();
    final c = t.isEmpty ? '#' : t[0];
    const umlauts = {'Ä': 'A', 'Ö': 'O', 'Ü': 'U'};
    final l = umlauts[c] ?? c;
    return RegExp(r'[A-Z]').hasMatch(l) ? l : '#';
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (!library.session.loggedIn) {
      return [MediaItem(id: 'login', title: 'Bitte in der App anmelden', playable: false)];
    }
    final books = library.books;
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return [for (final (id, title) in _shelves) _folder(id, title)];
      case AudioService.recentRootId:
        final last = book ?? library.lastPlayed;
        return last == null ? [] : [_bookItem(last)];
      case 'shelf:continue':
        return library.inProgress.take(30).map(_bookItem).toList();
      case 'shelf:device':
        final local = downloads.downloadedOrWanted.where((b) => downloads.isComplete(b)).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return local.map(_bookItem).toList();
      case 'shelf:new':
        return library.recentlyAdded.map(_bookItem).toList();
      case 'shelf:az':
        final letters = {for (final b in books) _letter(b)}.toList()..sort();
        return [
          for (final l in letters)
            _folder('az:$l', l == '#' ? '0–9 und andere' : l,
                subtitle: '${books.where((b) => _letter(b) == l).length} Bücher'),
        ];
    }
    if (parentMediaId.startsWith('az:')) {
      final l = parentMediaId.substring(3);
      final list = books.where((b) => _letter(b) == l).toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return list.map(_bookItem).toList();
    }
    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (!mediaId.startsWith('book:')) return null;
    final b = library.byId[mediaId.substring(5)];
    return b == null ? null : _bookItem(b);
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final b = library.byId[mediaId.startsWith('book:') ? mediaId.substring(5) : mediaId];
    if (b != null) await playBook(b);
  }

  /// Voice: "Hey Google, spiele <Titel> in Super-Papagei".
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final last = book ?? library.lastPlayed;
      if (last != null) await playBook(last);
      return;
    }
    final hits = (await search(query)).map((m) => library.byId[m.id.substring(5)]).whereType<Book>().toList();
    if (hits.isNotEmpty) await playBook(hits.first);
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    int score(Book b) {
      final hay = '${b.title} ${b.author} ${b.series ?? ''} ${b.narrator ?? ''}'.toLowerCase();
      if (!words.every(hay.contains)) return 0;
      var s = 1;
      if (b.title.toLowerCase().contains(query.toLowerCase())) s += 4;
      if (library.isStarted(b.id)) s += 2;
      return s;
    }
    final hits = library.books.map((b) => (b, score(b))).where((e) => e.$2 > 0).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return hits.take(20).map((e) => _bookItem(e.$1)).toList();
  }

  // ------------------------------------------------------------ system controls

  void _broadcast(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: Duration(milliseconds: (position * 1000).round()),
      bufferedPosition: Duration(milliseconds: (position * 1000).round()),
      speed: player.speed,
    ));
  }

  /// The current book's files are about to be deleted.
  /// Finished: the player forgets it, so Play cannot download it again by accident.
  /// Still being listened to: playback stops, the book stays in the mini player.
  Future<void> _onRemoved(Book b) async {
    final done = library.isPracticallyFinished(b);
    // Only the credits were left: count it as finished, so it leaves "Weiterhören".
    if (done && !library.isFinished(b.id)) {
      if (book?.id == b.id && _loaded) await _save(push: false);
      await library.markFinished(b.id, true);
    }
    if (book?.id != b.id) return;
    if (done) {
      // No final save here: it would overwrite the finished mark set above.
      _halt();
      await player.stop();
      _loaded = false;
      book = null;
      mediaItem.add(null);
      // Show the book you are still listening to instead, if there is one.
      final next = library.inProgress.where((x) => x.id != b.id).firstOrNull;
      if (next != null) {
        book = next;
        notifyListeners();
      }
    } else {
      await _save(push: true);
      _halt();
      await player.stop();
      _loaded = false;
      notifyListeners();
    }
  }

  /// Forget the current book (logout).
  Future<void> unload() async {
    await _save(push: true);
    _halt();
    await player.stop();
    _loaded = false;
    book = null;
    mediaItem.add(null);
    notifyListeners();
  }
}

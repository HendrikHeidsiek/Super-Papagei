import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../state/player.dart';
import 'theme.dart';
import '../state/updates.dart';

/// The parrot as a quiet line drawing, tinted to fit light and dark mode.
class ParrotLine extends StatelessWidget {
  final double size;
  final Color? color;
  const ParrotLine({super.key, this.size = 72, this.color});
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/parrot_line.png',
        width: size,
        height: size,
        color: color ?? context.c.tertiary,
        colorBlendMode: BlendMode.srcIn,
        excludeFromSemantics: true,
      );
}

/// Empty screen with the parrot, a title and one line of help.
class ParrotEmpty extends StatelessWidget {
  final String title;
  final String text;
  const ParrotEmpty({super.key, required this.title, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const ParrotLine(size: 84),
        const SizedBox(height: 14),
        Text(title, style: context.t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(text, style: context.t.bodyMedium!.copyWith(color: context.c.secondary), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Pull-to-refresh: the parrot nods while the library loads.
Widget parrotRefreshIndicator(BuildContext context, RefreshIndicatorMode mode, double pulled, double trigger, double _) {
  final pull = (pulled / trigger).clamp(0.0, 1.0);
  final busy = mode == RefreshIndicatorMode.refresh || mode == RefreshIndicatorMode.armed;
  return Center(
    child: Opacity(
      opacity: mode == RefreshIndicatorMode.inactive ? 0 : pull,
      child: _NoddingParrot(active: busy, tilt: (1 - pull) * -.5),
    ),
  );
}

class _NoddingParrot extends StatefulWidget {
  final bool active;
  final double tilt;
  const _NoddingParrot({required this.active, required this.tilt});
  @override
  State<_NoddingParrot> createState() => _NoddingParrotState();
}

class _NoddingParrotState extends State<_NoddingParrot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(_NoddingParrot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.active && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final nod = Curves.easeInOut.transform(_c.value) * .32;
        return Transform.rotate(
          angle: widget.active ? nod - .08 : widget.tilt,
          alignment: const Alignment(-.2, .5), // pivots at the neck
          child: child,
        );
      },
      child: const ParrotLine(size: 30),
    );
  }
}

/// "Über Super-Papagei": icon, name, version. Tapping the icon three times
/// wakes the parrot.
class AboutParrot extends StatefulWidget {
  const AboutParrot({super.key});
  @override
  State<AboutParrot> createState() => _AboutParrotState();
}

class _AboutParrotState extends State<AboutParrot> {
  String? _version;
  final List<DateTime> _taps = [];

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    });
  }

  void _tap() {
    final now = DateTime.now();
    _taps.removeWhere((t) => now.difference(t) > const Duration(milliseconds: 900));
    _taps.add(now);
    if (_taps.length >= 3) {
      _taps.clear();
      showParrot(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(children: [
        Semantics(
          button: true,
          label: 'App-Symbol',
          child: GestureDetector(
            onTap: _tap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Super-Papagei', style: context.t.titleMedium),
        const SizedBox(height: 2),
        Text(_version == null ? ' ' : 'Version $_version', style: context.t.bodySmall!.copyWith(color: c.secondary)),
        if (context.watch<AppUpdate>().available) ...[
          const SizedBox(height: 10),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(44, 36),
            color: c.fill,
            borderRadius: BorderRadius.circular(18),
            onPressed: () => context.read<AppUpdate>().download(),
            child: Text('Version ${context.watch<AppUpdate>().latestVersion} laden',
                style: TextStyle(color: c.tintText, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- the scene

class _Scene {
  final String asset;
  final List<String> line; // the parrot's balloon
  final List<String> call; // the balloon from off-stage
  final List<double> cues; // screech, line, call (seconds into the sound)
  final double end;
  const _Scene(this.asset, this.line, this.call, this.cues, this.end);

  factory _Scene.fromJson(Map<String, dynamic> j) => _Scene(
        j['src'] as String,
        [for (final x in (j['line'] as List? ?? [])) x as String],
        [for (final x in (j['call'] as List? ?? [])) x as String],
        [for (final x in j['cues'] as List) (x as num).toDouble()],
        (j['end'] as num).toDouble(),
      );
}

/// Without assets/parrot/scenes.json (public builds) the parrot just screeches.
const _screech = _Scene('assets/parrot/kraah.mp3', [], [], [0], .9);
List<_Scene>? _scenes;
String _stageTitle = 'Super-Papagei';
int _nextScene = math.Random().nextInt(2);

Future<List<_Scene>> _loadScenes() async {
  if (_scenes != null) return _scenes!;
  try {
    final j = jsonDecode(await rootBundle.loadString('assets/parrot/scenes.json')) as Map<String, dynamic>;
    _scenes = [for (final s in j['scenes'] as List) _Scene.fromJson(s as Map<String, dynamic>)];
    _stageTitle = (j['title'] as String?) ?? _stageTitle;
  } catch (_) {
    _scenes = const [];
  }
  return _scenes!;
}

Future<void> showParrot(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: 'Schließen',
    barrierColor: const Color(0xF50E1424),
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const _ParrotStage(),
    transitionsBuilder: (_, a, __, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
    ),
  ));
}

class _ParrotStage extends StatefulWidget {
  const _ParrotStage();
  @override
  State<_ParrotStage> createState() => _ParrotStageState();
}

class _ParrotStageState extends State<_ParrotStage> with SingleTickerProviderStateMixin {
  // Its own player that does not take over the audio session, so a running
  // audiobook keeps going (just quieter) instead of being interrupted.
  final AudioPlayer _sound = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  final Stopwatch _clock = Stopwatch();
  _Scene? _scene;
  int _seed = 0;
  // Kept from the start: in dispose() the widget can no longer look it up.
  late final PlayerController _book;

  @override
  void initState() {
    super.initState();
    _book = context.read<PlayerController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _play() async {
    if (_scene != null && _clock.elapsedMilliseconds < (_scene!.end + 1.1) * 1000) return;
    final list = await _loadScenes();
    if (!mounted) return;
    final sc = list.isEmpty ? _screech : list[_nextScene % list.length];
    _nextScene++;
    setState(() {
      _scene = sc;
      _seed = math.Random().nextInt(1 << 30);
    });
    _duck(true);
    try {
      await _sound.setAsset(sc.asset);
      unawaited(_sound.play());
    } catch (_) {}
    _clock
      ..reset()
      ..start();
    if (!_ticker.isActive) _ticker.start();
  }

  void _duck(bool on) {
    if (on && !_book.player.playing) return;
    _book.duck(on);
  }

  @override
  void dispose() {
    _duck(false);
    _ticker.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _clock.elapsedMilliseconds / 1000;
    final sc = _scene;
    if (sc != null && t > sc.end + 1.2 && _ticker.isActive) {
      _ticker.stop();
      _duck(false);
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(math.min(box.maxWidth - 32, box.maxHeight - pad.vertical - 140), 560.0);
      return DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none, fontWeight: FontWeight.w400),
        child: Stack(children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              button: true,
              label: 'Der Papagei. Tippen, dann krächzt er.',
              child: GestureDetector(
                onTap: _play,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 18))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset('assets/parrot/parrot.jpg', fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    if (sc != null)
                      Positioned.fill(
                        child: CustomPaint(painter: _ComicPainter(sc, t, _seed, reduce)),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(_stageTitle, style: TextStyle(fontFamily: 'ArchivoXC', fontWeight: FontWeight.w900, fontSize: 30, color: const Color(0xFFF3E6CF), letterSpacing: track(30))),
            const SizedBox(height: 4),
            Text('Tippen für mehr. Daneben tippen schließt.', style: TextStyle(fontSize: 13, color: const Color(0xFFF3E6CF).withValues(alpha: .6))),
          ]),
        ),
        Positioned(
          top: pad.top + 8,
          right: 12,
          child: CupertinoButton(
            padding: const EdgeInsets.all(10),
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.xmark_circle_fill, size: 30, color: Color(0x99F3E6CF), semanticLabel: 'Schließen'),
          ),
        ),
      ]),
      );
    });
  }
}

/// Draws the comic balloons at time [t] of the scene. Same shapes as on the
/// start page: a red sound burst, an oval balloon with its tail at the beak,
/// and a balloon from off-stage whose tail leaves the painting.
class _ComicPainter extends CustomPainter {
  final _Scene scene;
  final double t;
  final int seed;
  final bool reduce;
  _ComicPainter(this.scene, this.t, this.seed, this.reduce);

  static const ink = Color(0xFF120E0C);
  static const paper = Color(0xFFF8F0DF);
  static const red = Color(0xFFC8281E);

  @override
  void paint(Canvas canvas, Size size) {
    final p = size.width;
    final fadeAll = 1 - ((t - scene.end - .7) / .38).clamp(0.0, 1.0);
    if (fadeAll <= 0) return;
    const never = 1e9; // screech-only scene has no lines
    final c0 = scene.cues[0];
    final c1 = scene.cues.length > 1 ? scene.cues[1] : never;
    final c2 = scene.cues.length > 2 ? scene.cues[2] : never;
    // the screech is over once he talks
    final kGone = ((t - c1 - .16) / .24).clamp(0.0, 1.0);
    if (t >= c0 && kGone < 1) _burst(canvas, p, _grow(t - c0, bang: true), (1 - kGone) * fadeAll, 1 + kGone * .12);
    if (t >= c1) {
      _balloon(canvas, p, scene.line, p * .056, Offset(p * .76, p * .835), Offset(p * .795, p * .615), _grow(t - c1), fadeAll, seed + 1);
    }
    if (t >= c2) {
      _balloon(canvas, p, scene.call, p * .05, Offset(p * .26, p * .855), Offset(p * .015, p * 1.035), _grow(t - c2), fadeAll, seed + 2);
    }
  }

  /// 0..1 entrance: overshoots a little like the web version.
  double _grow(double dt, {bool bang = false}) {
    final x = (dt / (bang ? .52 : .44)).clamp(0.0, 1.0);
    if (reduce) return x;
    return Curves.easeOutBack.transform(x);
  }

  TextPainter _text(List<String> lines, double size, Color color) {
    final style = TextStyle(fontFamily: 'ArchivoXC', fontWeight: FontWeight.w900, fontSize: size, height: 1.0, letterSpacing: size * .02);
    final tp = TextPainter(
      text: TextSpan(text: lines.join('\n'), style: style.copyWith(color: color)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  void _paintText(Canvas canvas, List<String> lines, double size, Offset center, Color fill, {Color? stroke}) {
    if (stroke != null) {
      final sp = TextPainter(
        text: TextSpan(
          text: lines.join('\n'),
          style: TextStyle(
            fontFamily: 'ArchivoXC', fontWeight: FontWeight.w900, fontSize: size, height: 1.0, letterSpacing: size * .02,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * .12
              ..strokeJoin = StrokeJoin.round
              ..color = stroke,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      sp.paint(canvas, center - Offset(sp.width / 2, sp.height / 2));
    }
    final tp = _text(lines, size, fill);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _withLayer(Canvas canvas, double opacity, Offset origin, double scale, double rotate, void Function() body) {
    if (opacity <= 0 || scale <= 0) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(rotate);
    canvas.scale(scale);
    canvas.translate(-origin.dx, -origin.dy);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    body();
    canvas.restore();
    canvas.restore();
  }

  Paint get _shadow => Paint()
    ..color = const Color(0x61000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

  void _burst(Canvas canvas, double p, double g, double opacity, double extraScale) {
    final size = p * .074;
    final center = Offset(p * .79, p * .135);
    final tp = _text(const ['KRAAAH!'], size, paper);
    final rx = tp.width / 2 * 1.42 + size * .35, ry = tp.height / 2 * 1.9 + size * .45;
    final rnd = math.Random(seed);
    const spikes = 13;
    final rot = rnd.nextDouble() * math.pi;
    final path = Path();
    for (var k = 0; k < spikes * 2; k++) {
      final out = k.isEven;
      final r = out ? 1 + rnd.nextDouble() * .22 : .74 + rnd.nextDouble() * .06;
      final a = rot + k * math.pi / spikes;
      final pt = center + Offset(rx * r * math.cos(a), ry * r * math.sin(a));
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    final x = reduce ? 1.0 : g;
    final rotate = reduce ? 0.0 : (1 - (g.clamp(0.0, 1.0))) * -.42;
    _withLayer(canvas, opacity * (reduce ? g : math.min(1, g * 1.6)), center, (reduce ? 1 : x.clamp(0.0, 1.2)) * extraScale, rotate, () {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-7 * math.pi / 180);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawPath(path.shift(Offset(0, p * .008)), _shadow);
      canvas.drawPath(path, Paint()..color = red);
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, p * .0052)
        ..strokeJoin = StrokeJoin.round
        ..color = ink);
      _paintText(canvas, const ['KRAAAH!'], size, center, paper, stroke: ink);
      canvas.restore();
    });
  }

  void _balloon(Canvas canvas, double p, List<String> lines, double size, Offset center, Offset tip, double g, double opacity, int seed) {
    final tp = _text(lines, size, ink);
    final rx = tp.width / 2 * 1.26 + size * .5, ry = tp.height / 2 * 1.3 + size * .42;
    var cx = center.dx;
    final shift = math.min(0.0, p * .985 - (cx + rx)) + math.max(0.0, p * .015 - (cx - rx));
    cx += shift;
    final c = Offset(cx, center.dy);
    final rnd = math.Random(seed);
    final phi = math.atan2((tip.dy - c.dy) / ry, (tip.dx - c.dx) / rx);
    const gap = .24, n = 15;
    final pts = <Offset>[];
    for (var k = 0; k <= n; k++) {
      final a = phi + gap + k * (2 * math.pi - 2 * gap) / n;
      final wob = 1 + (k == 0 || k == n ? 0 : (rnd.nextDouble() - .5) * .07);
      pts.add(c + Offset(rx * wob * math.cos(a), ry * wob * math.sin(a)));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      path.cubicTo(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6, p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6, p2.dx, p2.dy);
    }
    Offset bend(Offset a, Offset b, double s) {
      final m = (a + b) / 2, d = b - a;
      return Offset(m.dx - d.dy * s, m.dy + d.dx * s);
    }
    final a0 = pts.first, b0 = pts.last;
    final q1 = bend(b0, tip, .12), q2 = bend(tip, a0, .12);
    path
      ..quadraticBezierTo(q1.dx, q1.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(q2.dx, q2.dy, a0.dx, a0.dy)
      ..close();
    _withLayer(canvas, opacity * (reduce ? g : math.min(1, g * 1.6)), tip, reduce ? 1 : g.clamp(0.0, 1.2), 0, () {
      canvas.drawPath(path.shift(Offset(0, p * .008)), _shadow);
      canvas.drawPath(path, Paint()..color = paper);
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, p * .0052)
        ..strokeJoin = StrokeJoin.round
        ..color = ink);
      _paintText(canvas, lines, size, c, ink);
    });
  }

  @override
  bool shouldRepaint(_ComicPainter old) => old.t != t || old.scene != scene || old.seed != seed;
}

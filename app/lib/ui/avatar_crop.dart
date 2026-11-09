import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens the "move and scale" screen for a picked photo.
/// Returns a square PNG of the chosen circle, or null when cancelled.
Future<Uint8List?> cropAvatar(BuildContext context, Uint8List bytes) async {
  final image = await decodeImageFromList(bytes);
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<Uint8List>(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _CropScreen(image),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _CropScreen extends StatefulWidget {
  final ui.Image image;
  const _CropScreen(this.image);

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  static const _outSize = 512.0;
  static const _maxZoom = 6.0;

  Rect _circle = Rect.zero; // crop circle in screen coordinates
  double _scale = 1; // screen pixels per image pixel
  Offset _offset = Offset.zero; // image top-left on screen
  double _minScale = 1;
  bool _ready = false;
  bool _busy = false;

  // gesture start state
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  ui.Image get _img => widget.image;

  void _layout(Size area) {
    final d = math.min(area.width, area.height) - 40;
    final circle = Rect.fromCenter(center: area.center(Offset.zero), width: d, height: d);
    if (circle == _circle && _ready) return;
    final minScale = d / math.min(_img.width, _img.height);
    if (!_ready) {
      // Start zoomed out as far as allowed, centred.
      _scale = minScale;
      _offset = circle.center - Offset(_img.width * _scale / 2, _img.height * _scale / 2);
    } else {
      // Area changed (rotation): keep the same image point in the circle centre.
      final p = (_circle.center - _offset) / _scale;
      _scale = math.max(_scale * d / _circle.width, minScale);
      _offset = circle.center - p * _scale;
    }
    _circle = circle;
    _minScale = minScale;
    _offset = _clamp(_offset, _scale);
    _ready = true;
  }

  /// The image must always cover the whole circle.
  Offset _clamp(Offset o, double s) {
    final w = _img.width * s, h = _img.height * s;
    return Offset(_fit(o.dx, _circle.right - w, _circle.left), _fit(o.dy, _circle.bottom - h, _circle.top));
  }

  // Like clamp, but tolerates lo > hi from rounding when the image is exactly as big as the circle.
  static double _fit(double v, double lo, double hi) => lo >= hi ? (lo + hi) / 2 : v.clamp(lo, hi);

  void _onStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    final s = (_startScale * d.scale).clamp(_minScale, _minScale * _maxZoom);
    // Keep the image point under the fingers where it started, then follow the drag.
    final imagePoint = (_startFocal - _startOffset) / _startScale;
    final o = d.localFocalPoint - imagePoint * s;
    setState(() {
      _scale = s;
      _offset = _clamp(o, s);
    });
  }

  void _onDoubleTap(TapDownDetails d) {
    // Double tap toggles between the full view and a 2.5x zoom at the tapped spot.
    final zoomedIn = _scale > _minScale * 1.05;
    final s = zoomedIn ? _minScale : _minScale * 2.5;
    final imagePoint = (d.localPosition - _offset) / _scale;
    setState(() {
      _scale = s;
      _offset = _clamp(zoomedIn ? _circle.center - Offset(_img.width * s / 2, _img.height * s / 2) : _circle.center - imagePoint * s, s);
    });
  }

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final src = Rect.fromLTWH(
      (_circle.left - _offset.dx) / _scale,
      (_circle.top - _offset.dy) / _scale,
      _circle.width / _scale,
      _circle.height / _scale,
    );
    final out = math.min(_outSize, src.width).roundToDouble();
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(_img, src, Rect.fromLTWH(0, 0, out, out),
        Paint()..filterQuality = FilterQuality.high);
    final pic = rec.endRecording();
    final result = await pic.toImage(out.toInt(), out.toInt());
    final data = await result.toByteData(format: ui.ImageByteFormat.png);
    pic.dispose();
    result.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(data?.buffer.asUint8List());
  }

  @override
  void dispose() {
    _img.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFFFF);
    final pad = MediaQuery.paddingOf(context);
    final buttonStyle = const TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.4);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: Column(
          children: [
            SizedBox(height: pad.top + 14),
            Text(
              'Verschieben und skalieren',
              style: buttonStyle.copyWith(fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                _layout(box.biggest);
                return Semantics(
                  label: 'Fotoausschnitt. Mit zwei Fingern zoomen, mit einem Finger verschieben.',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onStart,
                    onScaleUpdate: _onUpdate,
                    onDoubleTapDown: _onDoubleTap,
                    onDoubleTap: () {},
                    child: ClipRect(
                      child: CustomPaint(
                        size: box.biggest,
                        painter: _CropPainter(_img, _offset, _scale, _circle),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, math.max(pad.bottom, 12) + 4),
              child: Row(
                children: [
                  CupertinoButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text('Abbrechen', style: buttonStyle),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    onPressed: _busy ? null : _choose,
                    child: _busy
                        ? const CupertinoActivityIndicator(color: white)
                        : Text('Auswählen', style: buttonStyle.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Offset offset;
  final double scale;
  final Rect circle;
  _CropPainter(this.image, this.offset, this.scale, this.circle);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = offset & Size(image.width * scale, image.height * scale);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Dim everything outside the circle.
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
    canvas.drawPath(mask, Paint()..color = const Color(0xA6000000));
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x8CFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.offset != offset || old.scale != scale || old.circle != circle || old.image != image;
}

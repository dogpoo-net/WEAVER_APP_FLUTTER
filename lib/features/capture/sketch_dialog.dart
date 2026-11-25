import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'capture_models.dart';

Future<PhotoDraft?> showSketchDialog(BuildContext context) =>
    showDialog<PhotoDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SketchDialog(),
    );

class _Stroke {
  _Stroke(this.color, Offset start) : points = [start];
  final Color color;
  final List<Offset> points;

  bool near(Offset point) {
    var previous = points.first;
    for (final next in points) {
      final line = next - previous, offset = point - previous;
      final t = line.distanceSquared == 0
          ? 0.0
          : ((offset.dx * line.dx + offset.dy * line.dy) / line.distanceSquared)
                .clamp(0.0, 1.0);
      if ((point - (previous + line * t)).distance <= 12) return true;
      previous = next;
    }
    return false;
  }

  String get hex => '#${color.toARGB32().toRadixString(16).substring(2)}';
  String get svg {
    final start = points.first;
    if (points.length == 1)
      return '<circle cx="${start.dx}" cy="${start.dy}" r="2.5" fill="$hex"/>';
    final coords = points
        .map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}')
        .join(' ');
    return '<polyline points="$coords" fill="none" stroke="$hex" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>';
  }
}

class _SketchDialog extends StatefulWidget {
  const _SketchDialog();
  @override
  State<_SketchDialog> createState() => _SketchState();
}

class _SketchState extends State<_SketchDialog> {
  final strokes = <_Stroke>[];
  static const palette = [
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.brown,
  ];
  Color color = Colors.black;
  bool erasing = false;
  int? pointer;
  void draw(Offset p, {bool start = false}) {
    setState(() {
      if (erasing) {
        strokes.removeWhere((stroke) => stroke.near(p));
      } else if (start) {
        strokes.add(_Stroke(color, p));
      } else {
        strokes.last.points.add(p);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<Color>(
                tooltip: '색상 팔레트',
                icon: Icon(Icons.palette_outlined, color: color),
                onSelected: (next) => setState(() {
                  color = next;
                  erasing = false;
                }),
                itemBuilder: (_) => [
                  for (final c in palette)
                    PopupMenuItem(
                      value: c,
                      child: Icon(Icons.circle, color: c),
                    ),
                ],
              ),
              IconButton(
                tooltip: '지우개',
                isSelected: erasing,
                icon: const Icon(Icons.auto_fix_normal),
                onPressed: () => setState(() => erasing = !erasing),
              ),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close, size: 15),
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return SizedBox.square(
                  dimension: side,
                  child: ClipRect(
                    child: Listener(
                      key: const ValueKey("sketch-canvas"),
                      onPointerDown: (e) {
                        if (pointer != null) return;
                        pointer = e.pointer;
                        draw(e.localPosition * (512 / side), start: true);
                      },
                      onPointerMove: (e) {
                        if (pointer == e.pointer)
                          draw(e.localPosition * (512 / side));
                      },
                      onPointerUp: (e) {
                        if (pointer == e.pointer) pointer = null;
                      },
                      onPointerCancel: (e) {
                        if (pointer == e.pointer) pointer = null;
                      },
                      child: CustomPaint(painter: _SketchPainter(strokes)),
                    ),
                  ),
                );
              },
            ),
          ),
          TextButton(
            onPressed: strokes.isEmpty
                ? null
                : () {
                    final svg =
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512"><rect width="512" height="512" fill="white"/>${strokes.map((s) => s.svg).join()}</svg>';
                    Navigator.pop(
                      context,
                      PhotoDraft(utf8.encode(svg), '스케치.svg'),
                    );
                  },
            child: const Text('첨부'),
          ),
        ],
      ),
    ),
  );
}

class _SketchPainter extends CustomPainter {
  _SketchPainter(this.strokes);
  final List<_Stroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.scale(size.width / 512);
    for (final stroke in strokes) {
      final paint = Paint()..color = stroke.color;
      final first = stroke.points.first;
      canvas.drawCircle(first, 2.5, paint);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SketchPainter old) => true;
}

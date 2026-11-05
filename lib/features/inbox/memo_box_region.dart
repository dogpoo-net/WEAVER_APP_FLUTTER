import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'memo_boxes.dart';

/// Encloses every member's complete card, with room for the box label.
Rect? memoBoxCircleBounds(Iterable<Offset> positions) {
  final points = positions.toList();
  if (points.isEmpty) return null;
  final left = points.map((p) => p.dx).reduce(math.min);
  final right = points.map((p) => p.dx + 178).reduce(math.max);
  final top = points.map((p) => p.dy).reduce(math.min);
  final bottom = points.map((p) => p.dy + 84).reduce(math.max);
  final center = Offset((left + right) / 2, (top + bottom) / 2);
  var radius = 0.0;
  for (final point in points) {
    for (final corner in [point, point + const Offset(178, 0), point + const Offset(0, 84), point + const Offset(178, 84)]) {
      radius = math.max(radius, (corner - center).distance);
    }
  }
  return Rect.fromCircle(center: center, radius: radius + 32);
}

class MemoBoxRegion extends StatelessWidget {
  const MemoBoxRegion({super.key, required this.box, required this.bounds, this.onDrag, this.onDragEnd});
  final MemoBox box;
  final Rect bounds;
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onDragEnd;
  @override
  Widget build(BuildContext context) => Positioned.fromRect(rect: bounds, child: ClipOval(
    child: GestureDetector(behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => onDrag?.call(d.delta), onPanEnd: (_) => onDragEnd?.call(),
      child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
        color: Color(box.color).withValues(alpha: .10),
        border: Border.all(color: Color(box.color).withValues(alpha: .7), width: 1.5)),
        child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(32, 15, 32, 0),
          child: Text(box.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(box.color), fontSize: 13, fontWeight: FontWeight.w600)))),
      ),
    ),
  ));
}

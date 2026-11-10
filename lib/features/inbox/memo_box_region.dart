import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'memo_boxes.dart';

/// Encloses every member's complete card, with room for the box label.
Rect? memoBoxCircleBounds(Iterable<Offset> positions, {Map<Offset, Size> sizes = const {}}) {
  final points = positions.toList();
  if (points.isEmpty) return null;
  final left = points.map((p) => p.dx).reduce(math.min);
  final right = points.map((p) => p.dx + (sizes[p]?.width ?? 178)).reduce(math.max);
  final top = points.map((p) => p.dy).reduce(math.min);
  final bottom = points.map((p) => p.dy + (sizes[p]?.height ?? 84)).reduce(math.max);
  final center = Offset((left + right) / 2, (top + bottom) / 2);
  var radius = 0.0;
  for (final point in points) {
    final size = sizes[point] ?? const Size(178, 84);
    for (final corner in [point, point + Offset(size.width, 0), point + Offset(0, size.height), point + Offset(size.width, size.height)]) {
      radius = math.max(radius, (corner - center).distance);
    }
  }
  return Rect.fromCircle(center: center, radius: radius + 32);
}

bool memoBoxRegionsOverlap(Rect a, Rect b, {required bool rectangular, double gap = 24}) =>
  rectangular ? a.inflate(gap).overlaps(b) : (a.center - b.center).distance < (a.width + b.width) / 2 + gap;

class MemoBoxRegion extends StatelessWidget {
  const MemoBoxRegion({super.key, required this.box, required this.bounds, this.onDrag, this.onDragEnd, this.onDragCancel, this.onLiftStart, this.onLiftMove, this.highlighted = false, this.rectangular = false});
  final MemoBox box;
  final Rect bounds;
  final bool highlighted, rectangular;
  final ValueChanged<Offset>? onDrag, onLiftStart, onLiftMove;
  final VoidCallback? onDragEnd, onDragCancel;
  @override
  Widget build(BuildContext context) => Positioned.fromRect(rect: bounds, child: ClipPath(clipper: _RegionClipper(rectangular),
    child: GestureDetector(behavior: HitTestBehavior.opaque,
      onLongPressStart: onLiftStart == null ? null : (d) => onLiftStart!(d.globalPosition),
      onLongPressMoveUpdate: onLiftMove == null ? null : (d) => onLiftMove!(d.globalPosition),
      onLongPressEnd: onLiftStart == null ? null : (_) => onDragEnd?.call(),
      onPanUpdate: (d) => onDrag?.call(d.delta), onPanEnd: (_) => onDragEnd?.call(), onPanCancel: onDragCancel ?? onDragEnd,
      child: DecoratedBox(decoration: BoxDecoration(shape: rectangular ? BoxShape.rectangle : BoxShape.circle, borderRadius: rectangular ? BorderRadius.circular(24) : null,
        color: Color(box.color).withValues(alpha: highlighted ? .16 : .10),
        border: Border.all(color: Color(box.color).withValues(alpha: .7), width: highlighted ? 3 : 1.5)),
        child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(32, 15, 32, 0),
          child: Text(box.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(box.color), fontSize: 13, fontWeight: FontWeight.w600)))),
      ),
    ),
  ));
}

class _RegionClipper extends CustomClipper<Path> {
  const _RegionClipper(this.rectangular);
  final bool rectangular;
  @override
  Path getClip(Size size) => rectangular ? (Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)))) : (Path()..addOval(Offset.zero & size));
  @override
  bool shouldReclip(_RegionClipper old) => old.rectangular != rectangular;
}

import 'package:flutter/material.dart';

class PuzzleBorder extends OutlinedBorder {
  const PuzzleBorder({super.side});
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  PuzzleBorder copyWith({BorderSide? side}) => PuzzleBorder(side: side ?? this.side);
  @override
  ShapeBorder scale(double t) => PuzzleBorder(side: side.scale(t));
  @override
  Path getOuterPath(Rect r, {TextDirection? textDirection}) {
    final x = r.left, y = r.top, right = r.right, bottom = r.bottom;
    final cy = y + (r.height - 8) / 2;
    return Path()..moveTo(x + 12, y)..lineTo(x + 28, y)..lineTo(x + 34, y + 8)
      ..lineTo(x + 52, y + 8)..lineTo(x + 58, y)..lineTo(right - 20, y)
      ..quadraticBezierTo(right - 8, y, right - 8, y + 12)
      ..lineTo(right - 8, cy - 15)..lineTo(right, cy - 9)..lineTo(right, cy + 9)..lineTo(right - 8, cy + 15)
      ..lineTo(right - 8, bottom - 20)..quadraticBezierTo(right - 8, bottom - 8, right - 20, bottom - 8)
      ..lineTo(x + 58, bottom - 8)..lineTo(x + 52, bottom)..lineTo(x + 34, bottom)
      ..lineTo(x + 28, bottom - 8)..lineTo(x + 12, bottom - 8)
      ..quadraticBezierTo(x, bottom - 8, x, bottom - 20)
      ..lineTo(x, cy + 15)..lineTo(x + 8, cy + 9)..lineTo(x + 8, cy - 9)..lineTo(x, cy - 15)
      ..lineTo(x, y + 12)..quadraticBezierTo(x, y, x + 12, y)..close();
  }
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.solid && side.width > 0) { canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)),
      Paint()..color = side.color..style = PaintingStyle.stroke..strokeWidth = side.width); }
  }
}

/// Pick a nearby unoccupied dock, preserving every other block's position.
({String target, Offset position})? puzzleDock(String movingId, Map<String, Rect> nodes, {double threshold = 48}) {
  final moving = nodes[movingId];
  if (moving == null) return null;
  final candidates = <({String target, Offset position, double distance})>[];
  for (final entry in nodes.entries) {
    if (entry.key == movingId) continue;
    final target = entry.value;
    for (final position in [
      Offset(target.left, target.bottom - 16),
      Offset(target.left, target.top - moving.height + 16),
      Offset(target.right - 16, target.center.dy - moving.height / 2),
      Offset(target.left - moving.width + 16, target.center.dy - moving.height / 2),
    ]) {
      final distance = (moving.topLeft - position).distance;
      if (distance >= threshold || position.dx < 32 || position.dy < 32) continue;
      final rect = (position & moving.size).deflate(8);
      if (nodes.entries.any((other) => other.key != movingId && other.key != entry.key && rect.overlaps(other.value.deflate(8)))) continue;
      candidates.add((target: entry.key, position: position, distance: distance));
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.distance.compareTo(b.distance));
  return (target: candidates.first.target, position: candidates.first.position);
}

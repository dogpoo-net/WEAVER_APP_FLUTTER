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
    return Path()..moveTo(x + 12, y)..lineTo(x + 28, y)..lineTo(x + 34, y + 8)
      ..lineTo(x + 52, y + 8)..lineTo(x + 58, y)..lineTo(right - 12, y)
      ..quadraticBezierTo(right, y, right, y + 12)..lineTo(right, bottom - 20)
      ..quadraticBezierTo(right, bottom - 8, right - 12, bottom - 8)
      ..lineTo(x + 58, bottom - 8)..lineTo(x + 52, bottom)..lineTo(x + 34, bottom)
      ..lineTo(x + 28, bottom - 8)..lineTo(x + 12, bottom - 8)
      ..quadraticBezierTo(x, bottom - 8, x, bottom - 20)..lineTo(x, y + 12)
      ..quadraticBezierTo(x, y, x + 12, y)..close();
  }
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.solid && side.width > 0) { canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)),
      Paint()..color = side.color..style = PaintingStyle.stroke..strokeWidth = side.width); }
  }
}

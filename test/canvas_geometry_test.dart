import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';

void main() {
  for (final rectangular in [false, true]) {
    test('release moves only the dragged box toward the nearest free side ($rectangular)', () {
      const fixed = Rect.fromLTWH(300, 300, 200, 200);
      const moving = Rect.fromLTWH(470, 300, 200, 200);
      final shift = releaseBox(moving, [fixed], rectangular: rectangular);
      expect(shift.dx, closeTo(54, .1));
      expect(shift.dy.abs(), lessThan(.1));
      expect(memoBoxRegionsOverlap(moving.shift(shift), fixed, rectangular: rectangular), isFalse);
    });
    test('release clears several obstacles and stays within canvas ($rectangular)', () {
      const moving = Rect.fromLTWH(50, 50, 200, 200);
      const others = [Rect.fromLTWH(100, 50, 200, 200), Rect.fromLTWH(100, 270, 200, 200)];
      final result = moving.shift(releaseBox(moving, others, rectangular: rectangular));
      expect(result.left, greaterThanOrEqualTo(32));
      expect(result.top, greaterThanOrEqualTo(32));
      for (final other in others) {
        expect(memoBoxRegionsOverlap(result, other, rectangular: rectangular), isFalse);
      }
    });
  }
  test('near a stacked offset snaps without attracting distant cards', () {
    const target = Rect.fromLTWH(400, 400, 170, 96);
    expect(snapThought(const Rect.fromLTWH(404, 430, 170, 96), [target]), const Offset(-4, 2));
    expect(snapThought(const Rect.fromLTWH(700, 700, 170, 96), [target]), Offset.zero);
  });
}

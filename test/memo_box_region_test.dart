import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';

void main() {
  test('circle encloses full member cards and follows moved members', () {
    expect(memoBoxCircleBounds([]), isNull);
    final points = [const Offset(100, 100), const Offset(380, 260)];
    final bounds = memoBoxCircleBounds(points)!;
    for (final point in points) {
      for (final corner in [point, point + const Offset(178, 84)]) {
        expect((corner - bounds.center).distance, lessThan(bounds.width / 2));
      }
    }
    expect(memoBoxCircleBounds([points.first, const Offset(700, 500)])!.width, greaterThan(bounds.width));
  });
}

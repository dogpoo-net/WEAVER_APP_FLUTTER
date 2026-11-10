import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';

void main() {
  test('third and subsequent thoughts use a free stack slot', () {
    final positions = {'a': const Offset(100, 100), 'b': const Offset(100, 132),
      'c': const Offset(100, 164), 'drag': const Offset(300, 300)};
    expect(nextStackSlot('a', 'drag', positions), const Offset(100, 196));
    expect(nextStackSlot('a', 'b', positions), const Offset(100, 132));
  });
  test('only aligned stacks change position during layer edits', () {
    final positions = <String, Offset>{'a': const Offset(100, 100), 'b': const Offset(100, 132),
      'c': const Offset(100, 164), 'loose': const Offset(110, 145)};
    reorderStackPositions(positions, {'c', 'loose'}, up: true);
    expect(positions['c'], const Offset(100, 132));
    expect(positions['a'], const Offset(100, 100));
    expect(positions['loose'], const Offset(110, 145));
    reorderStackPositions(positions, {'c'}, up: false);
    expect(positions['c'], const Offset(100, 164));
    reorderStackPositions(positions, {'a', 'c', 'loose'});
    expect(positions['a'], const Offset(100, 164));
    expect(positions['c'], const Offset(100, 100));
    expect(positions['b'], const Offset(100, 132));
    expect(positions['loose'], const Offset(110, 145));
  });
  test('selected layers move one step together and reverse only selected slots', () {
    final order = ['a', 'b', 'c', 'd'];
    moveThoughtLayers(order, {'a', 'b'}, up: true);
    expect(order, ['c', 'a', 'b', 'd']);
    moveThoughtLayers(order, {'a', 'b'}, up: false);
    expect(order, ['a', 'b', 'c', 'd']);
    reverseThoughtLayers(order, {'a', 'c', 'd'});
    expect(order, ['d', 'b', 'c', 'a']);
    final layout = GraphLayout()..layers.addAll(order);
    expect(GraphLayout.fromJson(layout.toJson()).layers, order);
    expect(GraphLayout.fromJson({}).layers, isEmpty);
  });
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

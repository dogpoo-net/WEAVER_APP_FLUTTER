import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/graph_arrangement.dart';

void main() {
  test('default layout puts all tags above non-overlapping thoughts', () {
    final thoughts = List.generate(40, (i) => 'thought-$i');
    final tags = List.generate(14, (i) => 'tag-$i');
    final positions = <String, Offset>{}, tagPositions = <String, Offset>{};
    arrangeGraph(thoughts: thoughts, tags: tags, positions: positions, tagPositions: tagPositions);
    final boxes = [...positions.values.map(thoughtBounds), ...tagPositions.values.map(tagBounds)];
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        expect(boxes[i].overlaps(boxes[j]), isFalse);
      }
    }
    for (final tag in tagPositions.values) {
      for (final thought in positions.values) { expect(tagBounds(tag).bottom, lessThan(thought.dy)); }
    }
    final saved = Map.of(positions);
    positions[thoughts.first] = const Offset(100, 1200);
    arrangeGraph(thoughts: [...thoughts, 'new'], tags: [...tags, 'new-tag'], positions: positions, tagPositions: tagPositions);
    expect(positions[thoughts.first], const Offset(100, 1200));
    expect(positions[thoughts.last], saved[thoughts.last]);
    for (final id in thoughts) { expect(thoughtBounds(positions['new']!).overlaps(thoughtBounds(positions[id]!)), isFalse); }
  });

  test('routed tag and thought edges avoid every node in the default layout', () {
    final thoughts = List.generate(18, (i) => 'thought-$i');
    final tags = List.generate(8, (i) => 'tag-$i');
    final positions = <String, Offset>{}, tagPositions = <String, Offset>{};
    arrangeGraph(thoughts: thoughts, tags: tags, positions: positions, tagPositions: tagPositions);
    final bounds = {for (final e in positions.entries) e.key: thoughtBounds(e.value),
      for (final e in tagPositions.entries) e.key: tagBounds(e.value)};
    final router = GraphEdgeRouter(bounds);
    var lane = 0;
    void verify(String from, String to) {
      final path = router.route(from, to, lane++);
      expect(path.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < path.length; i++) {
        final start = path[i - 1], end = path[i];
        expect(start.dx == end.dx || start.dy == end.dy, isTrue);
        final steps = ((end - start).distance / 3).ceil();
        for (var j = 0; j <= steps; j++) {
          final point = Offset.lerp(start, end, steps == 0 ? 0 : j / steps)!;
          for (final entry in bounds.entries) {
            expect(entry.value.deflate(.5).contains(point), isFalse,
              reason: '$from → $to passes through ${entry.key} at $point');
          }
        }
      }
    }
    for (final thought in thoughts) {
      for (final tag in tags) { verify(thought, 'tag:$tag'); }
    }
    for (var i = 0; i < thoughts.length; i++) {
      for (var j = i + 1; j < thoughts.length; j++) { verify(thoughts[i], thoughts[j]); }
    }
  });
}

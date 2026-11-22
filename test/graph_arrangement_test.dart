import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/graph_arrangement.dart';

void main() {
  test('new tags avoid cards and preserve existing tag positions', () {
    final tags = ['one', 'two', 'three'];
    final card = const Rect.fromLTWH(640, 160, 230, 120);
    final positions = <String, Offset>{'tag:one': const Offset(100, 1200)};
    arrangeCanvasTags(tags: tags, cardBounds: [card], tagPositions: positions);
    expect(positions['tag:one'], const Offset(100, 1200));
    final bounds = positions.values.map(tagBounds).toList();
    for (var i = 0; i < bounds.length; i++) {
      expect(bounds[i].overlaps(card), isFalse);
      for (var j = i + 1; j < bounds.length; j++) {
        expect(bounds[i].overlaps(bounds[j]), isFalse);
      }
    }
  });

  test('routed tag and thought edges avoid every node in the default layout', () {
    final thoughts = List.generate(18, (i) => 'thought-$i');
    final tags = List.generate(8, (i) => 'tag-$i');
    final positions = <String, Offset>{};
    final tagPositions = <String, Offset>{};
    for (var i = 0; i < thoughts.length; i++) {
      positions[thoughts[i]] = Offset(640 + (i % 6) * 250, 500 + (i ~/ 6) * 160);
    }
    arrangeCanvasTags(tags: tags, cardBounds: positions.values.map((point) => point & const Size(170, 96)), tagPositions: tagPositions);
    final bounds = {for (final e in positions.entries) e.key: e.value & const Size(170, 96),
      for (final e in tagPositions.entries) e.key: tagBounds(e.value)};
    final router = GraphEdgeRouter(bounds);
    final interiors = {for (final e in bounds.entries) e.key: e.value.deflate(.5)};
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
          for (final entry in interiors.entries) {
            if (entry.value.contains(point)) fail( '$from → $to passes through ${entry.key} at $point');
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

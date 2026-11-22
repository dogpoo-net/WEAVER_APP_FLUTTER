import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';

void main() {
  test('separate objects move one paint slot in either direction', () {
    final positions = {
      'a': const Offset(100, 100),
      'photo': const Offset(500, 100),
      'b': const Offset(900, 100),
      'c': const Offset(1300, 100),
    };
    final before = Map.of(positions);
    final layers = ['a', 'photo', 'b', 'c'];

    stepCanvasLayers(layers, positions, {'photo'}, up: true, groups: {});
    expect(layers, ['a', 'b', 'photo', 'c']);

    stepCanvasLayers(layers, positions, {'photo'}, up: false, groups: {});
    expect(layers, ['a', 'photo', 'b', 'c']);
    expect(positions, before);
  });

  test('stack slots only change when the two stack members swap layers', () {
    final positions = {
      'a': const Offset(100, 100),
      'b': const Offset(100, 132),
      'x': const Offset(800, 100),
    };
    final layers = ['a', 'x', 'b'];

    stepCanvasLayers(layers, positions, {'a'}, up: true, groups: {});
    expect(layers, ['x', 'a', 'b']);
    expect(positions['a'], const Offset(100, 100));

    stepCanvasLayers(layers, positions, {'a'}, up: true, groups: {});
    expect(layers, ['x', 'b', 'a']);
    expect(positions['a'], const Offset(100, 132));
    expect(positions['b'], const Offset(100, 100));
  });
}

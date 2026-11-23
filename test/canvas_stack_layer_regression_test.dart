import 'dart:ui' show Size;
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

  test('photo crosses a visible overlap in one step without moving either card', () {
    final positions = {'photo': const Offset(100, 100), 'far': const Offset(700, 100),
      'card': const Offset(100, 132)};
    final original = Map.of(positions);
    final layers = ['photo', 'far', 'card'];
    final bounds = {for (final e in positions.entries) e.key: e.value & const Size(100, 100)};
    for (final up in [true, false]) {
      stepCanvasLayers(layers, positions, {'photo'}, up: up, groups: {}, bounds: bounds, photos: {'photo'});
      expect(layers.indexOf('photo') > layers.indexOf('card'), up);
      expect(positions, original);
    }
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

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

  test('up moves selected stack members earlier while loose cards move forward', () {
    final positions = {for (var i = 0; i < 3; i++) 's$i': Offset(100, 100 + 32.0*i),
      'x': const Offset(800,100), 'y': const Offset(900,100)};
    final original = Map.of(positions);
    final layers = ['s0','x','y','s1','s2'];
    final selected = {'s1','s2','x'};
    stepCanvasLayers(layers, positions, selected, up: true, groups: {});
    expect(layers, ['s1','y','x','s2','s0']);
    expect(positions['s1'], original['s0']);
    expect(positions['s2'], original['s1']);
    stepCanvasLayers(layers, positions, selected, up: false, groups: {});
    expect(layers, ['s0','x','y','s1','s2']);
    expect(positions, original);
  });
}

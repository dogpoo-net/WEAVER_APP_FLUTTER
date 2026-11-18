import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';
void main() {
  test('moving upwards passes behind stack neighbor despite unrelated layers', () {
    final positions = {'a': const Offset(100,100), 'b': const Offset(100,132), 'x': const Offset(800,100)};
    final layers = ['a','x','b'];
    moveThoughtLayers(layers, {'b'}, up:false);
    reorderStackPositions(positions, {'b'}, up:true);
    alignStackLayers(layers, positions, {});
    expect(positions['b'], const Offset(100,100));
    expect(layers.indexOf('b'), lessThan(layers.indexOf('a')));
  });
}

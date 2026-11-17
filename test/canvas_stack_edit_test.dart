import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_stack_edit.dart';

void main() {
  final before = {'a': const Offset(100,100), 'b': const Offset(100,132),
    'c': const Offset(100,164), 'd': const Offset(100,196), 'other': const Offset(500,500)};
  test('removing middle slot shifts all lower cards, preserving unrelated cards', () {
    final next = {...before}..remove('b');
    closeVacatedStackSlots(next,before,{'b'});
    expect(next['c'],before['b']); expect(next['d'],before['c']);
    expect(next['a'],before['a']); expect(next['other'],before['other']);
  });
  test('multi move closes all vacant slots and preserves moved destination', () {
    final next = {...before,'b':const Offset(800,800),'c':const Offset(800,832)};
    closeVacatedStackSlots(next,before,{'b','c'});
    expect(next['d'],before['b']); expect(next['b'],const Offset(800,800));
    expect(next['c'],const Offset(800,832));
  });
  test('arbitrary overlaps do not become a stack', () {
    final prior = {'a': const Offset(100,100), 'b':const Offset(100,150)};
    final next = {...prior}..remove('a');
    closeVacatedStackSlots(next,prior,{'a'});
    expect(next['b'],prior['b']);
  });
  test('tag anchor uses the exposed strip and facing left/right border', () {
    const card=Rect.fromLTWH(100,100,230,120), cover=Rect.fromLTWH(100,132,230,120);
    expect(exposedSideAnchor(card,[cover],const Offset(0,500)),const Offset(100,116));
    expect(exposedSideAnchor(card,[cover],const Offset(600,500)),const Offset(330,116));
    expect(exposedSideAnchor(card,[],const Offset(600,500)),const Offset(330,160));
    expect(exposedSideAnchor(card,[card],const Offset(0,0)),isNull);
  });
}

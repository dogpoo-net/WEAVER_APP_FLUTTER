import 'package:flutter/material.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';

void main() {
  testWidgets('box border, empty interior and title all drag the group', (tester) async {
    var shift = Offset.zero;
    var interior = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onPanUpdate: (_) => interior++)),
      MemoBoxRegion(box: MemoBox('상자'), bounds: const Rect.fromLTWH(20, 20, 200, 200), onDrag: (d) => shift += d),
    ]))));
    await tester.dragFrom(const Offset(120, 25), const Offset(35, 0));
    expect(shift.dx, greaterThan(0));
    final borderShift = shift;
    await tester.dragFrom(const Offset(120, 120), const Offset(35, 0));
    expect(shift.dx, greaterThan(borderShift.dx));
    final interiorShift = shift;
    await tester.drag(find.text('상자'), const Offset(35, 0));
    expect(shift.dx, greaterThan(interiorShift.dx));
    expect(interior, 0);
    expect(tester.takeException(), isNull);
  });
}

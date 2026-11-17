import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/graph_layout.dart';

void main() {
  testWidgets('a touch above the thought belongs to the canvas', (tester) async {
    var taps = 0, canvasTaps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: () => canvasTaps++,
      child: Center(child: ThoughtInteraction(size: const Size(178, 84), desktop: false,
        onMove: (_) {}, onResize: (_, shift) {}, onDrop: (_) {}, onEnd: () {},
        onTap: () => taps++, child: const ColoredBox(color: Colors.blue))),
    ))));
    final top = tester.getTopLeft(find.byType(ThoughtInteraction));
    await tester.tapAt(top + const Offset(80, -3));
    expect(taps, 0); expect(canvasTaps, 1);
    await tester.tapAt(top + const Offset(80, 20));
    expect(taps, 1); expect(canvasTaps, 1);
  });
  for (final desktop in [true, false]) {
    testWidgets('resize changes the card and preserves font size (desktop=$desktop)', (tester) async {
      var size = const Size(178, 84);
      var drops = 0;
      final view = TransformationController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InteractiveViewer(
        transformationController: view,
        child: Center(child: StatefulBuilder(builder: (context, update) => ThoughtInteraction(
          size: size, desktop: desktop, onMove: (_) {}, onDrop: (_) => drops++, onEnd: () {},
          onTap: () {}, onResize: (next, shift) => update(() => size = next),
          child: const Text('같은 폰트 크기로 긴 생각의 내용을 계속 표시합니다.', style: TextStyle(fontSize: 14)),
        ))),
      ))));
      if (desktop) {
        await tester.drag(find.byKey(const ValueKey('resize-right-bottom')), const Offset(90, 60));
      } else {
        final center = tester.getCenter(find.byType(ThoughtInteraction));
        // Both fingers start inside the visible card border.
        final distance = size.width / 2 - 2;
        final a = await tester.startGesture(center - Offset(distance, 0), pointer: 1);
        final b = await tester.startGesture(center + Offset(distance, 0), pointer: 2);
        await tester.pump();
        for (var step = 1; step <= 4; step++) {
          await a.moveTo(center - Offset(distance + step * 12, 0));
          await b.moveTo(center + Offset(distance + step * 12, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await a.up(); await b.up();
      }
      await tester.pumpAndSettle();
      expect(size.width, greaterThan(178));
      expect(size.height, greaterThan(84));
      expect(tester.widget<Text>(find.text('같은 폰트 크기로 긴 생각의 내용을 계속 표시합니다.')).style!.fontSize, 14);
      expect(view.value.getMaxScaleOnAxis(), 1);
      expect(drops, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      view.dispose();
    });
  }
  for (final spec in [
    ('left',true,false,true,false),('right',false,false,true,false),
    ('top',false,true,false,true),('bottom',false,false,false,true),
    ('left-top',true,true,true,true),('right-top',false,true,true,true),
    ('left-bottom',true,false,true,true),('right-bottom',false,false,true,true),
  ]) {
    testWidgets('double click fits only the requested edges ${spec.$1}', (tester) async {
      Size? fitted;Offset? shift;var ends=0;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:ThoughtInteraction(
        size:const Size(300,200),desktop:true,child:const Text('메모'),
        fitSize:(horizontal,vertical){expect(horizontal,spec.$4);expect(vertical,spec.$5);return const Size(210,110);},
        onMove:(_){},onDrop:(_){},onTap:(){},onEnd:()=>ends++,
        onResize:(next,delta){fitted=next;shift=delta;},
      )))));
      final handle=find.byKey(ValueKey('resize-${spec.$1}'));
      await tester.tap(handle);await tester.pump(const Duration(milliseconds:50));await tester.tap(handle);await tester.pumpAndSettle();
      expect(fitted,Size(spec.$4?210:300,spec.$5?110:200));
      expect(shift,Offset(spec.$2?90:0,spec.$3?90:0));expect(ends,1);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('card sizes survive layout serialization and legacy layouts use defaults', () {
    final layout = GraphLayout()..sizes['thought'] = const Offset(320, 240);
    expect(GraphLayout.fromJson(layout.toJson()).sizes['thought'], const Offset(320, 240));
    expect(GraphLayout.fromJson({}).sizes, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){for(final blocks in [false,true]){for(final intoBox in [false,true]){
 testWidgets('selected group long press transfers together blocks=$blocks box=$intoBox',(tester)async{
 tester.view.physicalSize=const Size(1400,1000);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
 final a=elements.add('a'),b=elements.add('b'),c=elements.add('c'),d=elements.add('d');
 final source=MemoBox('source',ids:[a.id,b.id,c.id]);final destination=MemoBox('destination',ids:[d.id]);memoBoxes.add(source);if(intoBox)memoBoxes.add(destination);
 final layout=blocks?pageGraphLayout.blockLayout:pageGraphLayout;
 layout.positions.addAll({a.id:const Offset(500,500),b.id:const Offset(800,500),c.id:const Offset(500,800),d.id:const Offset(1800,1200)});
 layout.viewport=(Matrix4.identity()..scaleByDouble(.5,.5,.5,1)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){})));await tester.pumpAndSettle();
 await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);await tester.pump();
 for(final id in [a.id,b.id]){await tester.tapAt(tester.getCenter(find.byKey(ValueKey('canvas-thought-$id'))));await tester.pump();}
 await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);await tester.pump();
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'2');
 final startA=layout.positions[a.id]!,startB=layout.positions[b.id]!;
 final from=tester.getCenter(find.byKey(ValueKey('canvas-thought-${a.id}')));
 final scene=tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));
 final to=intoBox?tester.getCenter(find.byKey(ValueKey('canvas-thought-${d.id}'))):scene.localToGlobal(const Offset(1900,1500));
 final gesture=await tester.startGesture(from);await tester.pump(const Duration(milliseconds:650));await gesture.moveTo(to);await tester.pump();await gesture.up();await tester.pumpAndSettle();
 expect(source.elementIds,{c.id});if(intoBox)expect(destination.elementIds,containsAll([a.id,b.id,d.id]));
 expect(layout.positions[a.id]!-startA,layout.positions[b.id]!-startB);
 expect(elements.records.length,4);expect(tester.takeException(),isNull);
 await tester.pumpWidget(const SizedBox());
 });
}}}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){testWidgets('Ctrl marquee selects and moves a tag together with its memo',(tester)async{
 tester.view.physicalSize=const Size(1200,900);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
 elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();final a=elements.add('태그 메모');a.tags.add('검색');
 final layout=pageGraphLayout.blockLayout;
 layout.positions[a.id]=const Offset(500,500);layout.tags['tag:검색']=const Offset(900,540);layout.viewport=(Matrix4.identity()..setTranslationRaw(-400,-400,0)).storage.toList();
 await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
 await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);await tester.pump();
 final box=tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));final gesture=await tester.startGesture(box.localToGlobal(const Offset(460,460)));
 await gesture.moveTo(box.localToGlobal(const Offset(1040,650)));await tester.pump();await gesture.up();
 await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);await tester.pumpAndSettle();
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'2');
 final beforeMemo=layout.positions[a.id]!,beforeTag=layout.tags['tag:검색']!;
 await tester.dragFrom(tester.getCenter(find.byKey(ValueKey('canvas-thought-${a.id}'))),const Offset(100,120));await tester.pumpAndSettle();
 final shift=layout.positions[a.id]!-beforeMemo;
 expect(shift.distance,greaterThan(40));expect(layout.tags['tag:검색']!-beforeTag,shift);
 await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('graph-tag-검색'))));await tester.pumpAndSettle();
 expect(tester.widget<Text>(find.byKey(const ValueKey('selection-count'))).data,'1');
 await tester.drag(find.byKey(const ValueKey('graph-tag-검색')),const Offset(80,0));await tester.pumpAndSettle();
 expect(tester.takeException(),isNull);
 await tester.pumpWidget(const SizedBox());
});}

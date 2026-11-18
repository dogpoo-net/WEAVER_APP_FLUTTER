import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_link_text.dart';
import 'package:weaver/features/inbox/element_binding.dart';
import 'package:weaver/features/inbox/element_store.dart';
void main(){for(final enabled in [true,false]){
 testWidgets('canvas link enabled=$enabled preserves parent gesture routing',(tester)async{
  elements.clear();final target=elements.add('연결된 생각');var parentTaps=0;var moves=0;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:GestureDetector(onTap:()=>parentTaps++,onPanUpdate:(_)=>moves++,child:CanvasLinkText(text:'링크',links:[ElementBinding('label:${target.id}',0,2)],enabled:enabled))))));
  final text=find.descendant(of:find.byType(CanvasLinkText),matching:find.byType(Text));
  final span=(tester.widget<Text>(text).textSpan! as TextSpan).children!.first as TextSpan;
  expect(span.mouseCursor,enabled?SystemMouseCursors.click:MouseCursor.defer);
  await tester.drag(text,const Offset(70,0));await tester.pumpAndSettle();expect(moves,greaterThan(0));expect(find.byType(AlertDialog),findsNothing);
  await tester.tap(text);await tester.pumpAndSettle();
  expect(parentTaps,enabled?0:1);expect(find.byType(AlertDialog),enabled?findsOneWidget:findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
}}

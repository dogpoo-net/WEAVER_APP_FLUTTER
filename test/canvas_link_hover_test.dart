import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_link_text.dart';
import 'package:weaver/features/inbox/element_binding.dart';
void main(){
 for(final memo in [true,false]){
  testWidgets('hover uses solid underline then restores memo=$memo style',(tester)async{
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:CanvasLinkText(text:'링크',links:[ElementBinding(memo?'label:target':'project:target',0,2)],enabled:true)))));
   final text=find.descendant(of:find.byType(CanvasLinkText),matching:find.byType(Text));
   TextStyle style()=>((tester.widget<Text>(text).textSpan! as TextSpan).children!.first as TextSpan).style!;
   final original=style();
   expect(original.decoration,memo?TextDecoration.underline:TextDecoration.none);
   final mouse=await tester.createGesture(kind:PointerDeviceKind.mouse);
   await mouse.addPointer(location:Offset.zero);await mouse.moveTo(tester.getCenter(text));await tester.pumpAndSettle();
   expect(style().decoration,TextDecoration.underline);expect(style().decorationStyle,TextDecorationStyle.solid);expect(style().color,original.color);
   await mouse.moveTo(Offset.zero);await tester.pumpAndSettle();expect(style(),original);
   await mouse.removePointer();await tester.pumpWidget(const SizedBox());
  });
 }
}

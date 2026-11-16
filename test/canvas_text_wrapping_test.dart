import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
 for(final blocks in [false,true]) {
 testWidgets('canvas wraps explicit and long lines in available card space ($blocks)',(tester)async{
  elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();
  final text=List.generate(blocks?4:7,(i)=>i==1?'':'내용 ${i+1}').join('\n');
  final record=elements.add(text);
  final layout=blocks?pageGraphLayout.blockLayout:pageGraphLayout;
  layout.positions[record.id]=const Offset(500,500);
  if(!blocks)layout.sizes[record.id]=const Offset(230,160);
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){})));
  await tester.pumpAndSettle();
  final rich=find.descendant(of:find.text(text),matching:find.byType(RichText));
  final paragraph=tester.renderObject<RenderParagraph>(rich);
  final start=paragraph.getBoxesForSelection(const TextSelection(baseOffset:0,extentOffset:3));
  final end=paragraph.getBoxesForSelection(TextSelection(baseOffset:text.length-3,extentOffset:text.length));
  expect(end,isNotEmpty);expect(end.first.top,greaterThan(start.first.bottom*2));
  final cardSize=tester.getSize(find.byKey(ValueKey('canvas-thought-${record.id}')));
  final longText=List.filled(30,'너비에 맞게 줄바꿈').join(' ');
  elements.update(record.text,longText);await tester.pumpAndSettle();
  final wrapped=tester.renderObject<RenderParagraph>(find.descendant(of:find.text(longText),matching:find.byType(RichText)));
  final boxes=wrapped.getBoxesForSelection(TextSelection(baseOffset:0,extentOffset:longText.length));
  expect(boxes.map((box)=>box.top).toSet().length,greaterThan(1));
  expect(tester.getSize(find.byKey(ValueKey('canvas-thought-${record.id}'))),cardSize);
  expect(wrapped.size.height,lessThanOrEqualTo(cardSize.height));
  expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
 }
}

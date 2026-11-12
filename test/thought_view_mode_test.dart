import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/thought_filters.dart';
void main(){
 testWidgets('photo grid zoom stops at one column and hides in detail mode',(tester)async{
  elements.clear();final filters=ThoughtFilterSelection();
  await tester.pumpWidget(MaterialApp(home:AttachmentCollection(audio:false,selector:const SizedBox(),filters:filters)));
  await tester.tap(find.byTooltip('확대'));await tester.pumpAndSettle();expect(find.text('1열'),findsOneWidget);expect(tester.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='확대')).onPressed,isNull);
  await tester.tap(find.byTooltip('정렬'));await tester.pumpAndSettle();await tester.tap(find.text('자세히'));await tester.pumpAndSettle();expect(find.byTooltip('확대'),findsNothing);
  await tester.pumpWidget(const SizedBox());filters.dispose();
 });
 testWidgets('thought square toggle and column zoom preserve square geometry',(tester)async{
 elements.clear();final record=elements.add('정사각형 메모');
 await tester.pumpWidget(const MaterialApp(home:ThoughtBoxView(notes:[])));
 expect(find.byTooltip('닫힌 생각 보기'),findsNothing);
 await tester.tap(find.byTooltip('행으로 보기 · 바둑판으로 전환'));await tester.pumpAndSettle();
 expect(find.byKey(const ValueKey('thought-square-grid')),findsOneWidget);
 final size=tester.getSize(find.byKey(ValueKey('thought-${record.id}')));expect(size.width,closeTo(size.height,.1));
 await tester.tap(find.byTooltip('확대'));await tester.pumpAndSettle();expect(find.text('1열'),findsOneWidget);
 expect(tester.widget<IconButton>(find.byWidgetPredicate((w)=>w is IconButton && w.tooltip=='확대')).onPressed,isNull);
 await tester.tap(find.byTooltip('바둑판식 보기 · 행으로 전환'));await tester.pumpAndSettle();expect(find.byKey(const ValueKey('thought-square-grid')),findsNothing);
 await tester.pumpWidget(const SizedBox());elements.clear();
});}

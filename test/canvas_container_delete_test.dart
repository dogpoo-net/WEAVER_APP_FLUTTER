import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
void main(){
 setUp((){elements.clear();memoBoxes.clear();memoBoxFolders.clear();memoBoxFolderParents.clear();pageGraphLayout=GraphLayout();});
 for(final blocks in [false,true]){
 testWidgets('canvas create menu and box X preserve contents ($blocks)',(tester)async{
  final record=elements.add('보존할 생각');final box=MemoBox('대상',ids:[record.id]);memoBoxes.add(box);
  var saves=0;await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:blocks,onChanged:(){},onSave:()async{saves++;})));
  await tester.pumpAndSettle();await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();
  expect(find.text('생각 만들기'),findsOneWidget);expect(find.text('상자 만들기'),findsOneWidget);expect(find.text('상자 삭제'),findsOneWidget);
  await tester.tap(find.text('생각 만들기'));await tester.pumpAndSettle();await tester.tap(find.text('취소'));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('대상 상자 삭제'));await tester.pumpAndSettle();
  expect(find.text('삭제하시겠습니까?'),findsOneWidget);await tester.tap(find.text('취소'));await tester.pumpAndSettle();expect(memoBoxes,contains(box));
  await tester.tap(find.byTooltip('대상 상자 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();
  expect(memoBoxes, isNot(contains(box)));expect(elements.records,contains(record.text));expect(ensureUnclassifiedBox().elementIds,contains(record.id));expect(saves,1);expect(elements.trash,isEmpty);
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
 }
 testWidgets('folder X promotes direct children and keeps nested contents',(tester)async{
  memoBoxFolders.addAll(['상위','대상','하위']);memoBoxFolderParents.addAll({'대상':'상위','하위':'대상'});
  final record=elements.add('보존');final box=MemoBox('직접',folder:'대상',ids:[record.id]);final nested=MemoBox('깊이',folder:'하위');memoBoxes.addAll([box,nested]);
  await tester.pumpWidget(MaterialApp(home:ThoughtPage(blocks:true,onChanged:(){})));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('대상 폴더 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();
  expect(memoBoxFolders, isNot(contains('대상')));expect(box.folder,'상위');expect(memoFolderParent('하위'),'상위');expect(nested.folder,'하위');expect(elements.records,contains(record.text));
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
 test('deleting root folder promotes contents to root and protects unclassified',(){
  memoBoxFolders.addAll(['root','child']);memoBoxFolderParents['child']='root';final box=MemoBox('box',folder:'root');memoBoxes.add(box);
  removeMemoFolderKeepingContents('root');expect(box.folder,isNull);expect(memoFolderParent('child'),isNull);expect(memoBoxFolders,contains('child'));
  final unclassified=ensureUnclassifiedBox();removeMemoBoxesKeepingThoughts({unclassified.name});expect(memoBoxes,contains(unclassified));
 });
}

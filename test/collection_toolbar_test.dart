import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/grid_columns_preference.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/thought_filters.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';

void main(){
 setUp((){SharedPreferences.setMockInitialValues({});elements.clear();memoBoxes.clear();thoughtSquareViewCache=null;
  thoughtGridColumns=GridColumnsPreference('weaver.thoughtGridColumns.v1');photoGridColumns=GridColumnsPreference('weaver.photoGridColumns.v1');audioGridColumns=GridColumnsPreference('weaver.audioGridColumns.v1');});
 testWidgets('wide thought toolbar reaches both padded edges',(tester)async{
  tester.view.physicalSize=const Size(1600,900);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  elements.add('메모');await tester.pumpWidget(const MaterialApp(home:ThoughtBoxView(notes:[])));await tester.pumpAndSettle();
  expect(tester.getTopLeft(find.text('생각 1개')).dx,12);
  expect(tester.getTopRight(find.byTooltip('축소')).dx,1588);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('audio uses six/two columns and remembers its own zoom; both media counts remain in details',(tester)async{
  final filters=ThoughtFilterSelection();addTearDown(filters.dispose);
  elements.add('음성 메모').recordings.add(const VoiceAttachment('clip',2000));
  Widget page(bool audio,{TargetPlatform platform=TargetPlatform.linux})=>MaterialApp(theme:ThemeData(platform:platform),home:AttachmentCollection(key:ValueKey(audio),audio:audio,selector:const SizedBox(),filters:filters));
  await tester.pumpWidget(page(true));await tester.pumpAndSettle();expect(find.text('음성 1개'),findsOneWidget);expect(find.text('6열'),findsOneWidget);
  await tester.tap(find.byTooltip('확대'));await tester.pumpAndSettle();expect(find.text('5열'),findsOneWidget);
  await tester.pumpWidget(page(false));await tester.pumpAndSettle();expect(find.text('사진 0개'),findsOneWidget);expect(find.text('6열'),findsOneWidget);
  await tester.pumpWidget(page(true));await tester.pumpAndSettle();expect(find.text('5열'),findsOneWidget);
  tester.widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>)).onSelected!(true);await tester.pumpAndSettle();expect(find.text('음성 1개'),findsOneWidget);expect(find.byTooltip('확대'),findsNothing);
  await tester.pumpWidget(const SizedBox());SharedPreferences.setMockInitialValues({});audioGridColumns=GridColumnsPreference('weaver.audioGridColumns.v1');
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page(true,platform:TargetPlatform.iOS));await tester.pumpAndSettle();expect(find.text('2열'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('thought menu creates memo and deletes only its selected container',(tester)async{
  final filters=ThoughtFilterSelection();addTearDown(filters.dispose);var saves=0;saveWorkspaceContent=()async{saves++;};addTearDown(()=>saveWorkspaceContent=null);
  final box=MemoBox('상자');memoBoxes.add(box);filters.boxes.add(box);
  await tester.pumpWidget(MaterialApp(home:ThoughtBoxView(notes:[],filters:filters)));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();expect(find.text('생각 만들기'),findsOneWidget);expect(find.text('상자 만들기'),findsOneWidget);expect(find.text('상자 삭제'),findsOneWidget);
  await tester.tap(find.text('생각 만들기'));await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of:find.byType(AlertDialog),matching:find.byType(TextField)),'새 생각');await tester.tap(find.text('만들기'));await tester.pumpAndSettle();
  final id=elements.records['새 생각']!.id;expect(box.elementIds,contains(id));expect(saves,1);
  await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();await tester.tap(find.text('상자 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();
  expect(find.textContaining('포함된 생각은 삭제하지 않고 미분류로 이동합니다.'),findsOneWidget);
  await tester.tap(find.text('삭제'));await tester.pumpAndSettle();expect(memoBoxes.contains(box),false);expect(elements.records.containsKey('새 생각'),true);expect(ensureUnclassifiedBox().elementIds,contains(id));expect(saves,2);
  await tester.pumpWidget(const SizedBox());
 });
}

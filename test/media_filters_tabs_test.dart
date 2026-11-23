import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/grid_columns_preference.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/thought_filters.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main(){
 setUp((){SharedPreferences.setMockInitialValues({});elements.clear();memoBoxes.clear();pageGraphLayout=GraphLayout();photoGridColumns=GridColumnsPreference('photo-test');audioGridColumns=GridColumnsPreference('audio-test');});
 testWidgets('two selected boxes show only their subtrees and delete all removes descendants', (tester) async {
   final inside = elements.add('하위 생각'), outside = elements.add('외부 생각');
   final parent = MemoBox('상위'), second = MemoBox('둘째');
   memoBoxes.addAll([parent, second, MemoBox('하위', folder: '상위', ids: [inside.id]),
     MemoBox('외부', ids: [outside.id])]);
   final filters = ThoughtFilterSelection(initialBox: parent)..toggle(second, null);
   await tester.pumpWidget(MaterialApp(home: ThoughtPage(filters: filters, onChanged: () {})));
   await tester.pumpAndSettle();
   expect(find.byKey(const ValueKey('box-region-외부')), findsNothing);
   expect(find.byKey(const ValueKey('box-region-하위')), findsOneWidget);
   expect(find.byKey(ValueKey('canvas-thought-${inside.id}')), findsOneWidget);
   expect(find.byKey(ValueKey('canvas-thought-${outside.id}')), findsNothing);
   await tester.tap(find.byTooltip('상위 상자 삭제'));
   await tester.pumpAndSettle();
   await tester.tap(find.text('모두 삭제'));
   await tester.pumpAndSettle();
   expect(memoBoxes.map((box) => box.name), isNot(contains('하위')));
   expect(elements.byId(inside.id), isNull);
   expect(elements.byId(outside.id), isNotNull);
   await tester.pumpWidget(const SizedBox());
   filters.dispose();
 });
 testWidgets('duplicate box name can be corrected in the same dialog', (tester) async {
   memoBoxes.add(MemoBox('기존'));
   await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
     TextButton(onPressed: () => createMemoBox(context), child: const Text('추가'))))));
   await tester.tap(find.text('추가'));
   await tester.pumpAndSettle();
   await tester.enterText(find.byType(TextField), ' 기존 ');
   await tester.tap(find.text('만들기'));
   await tester.pumpAndSettle();
   expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, '이미 사용 중인 상자 이름입니다.');
   await tester.enterText(find.byType(TextField), '새 상자');
   await tester.testTextInput.receiveAction(TextInputAction.done);
   await tester.pumpAndSettle();
   expect(find.byType(AlertDialog), findsNothing);
   expect(memoBoxes.map((box) => box.name), ['기존', '새 상자']);
 });
 for(final audio in [false,true]){
 testWidgets('media footer filters by box and hashtag with OR semantics ($audio)',(tester)async{
  final a=elements.add('첫 메모 #첫째'),b=elements.add('둘째 메모 #둘째');
  for(final r in [a,b]){r.photos.add(PhotoAttachment('photo-${r.id}','사진'));r.recordings.add(VoiceAttachment('voice-${r.id}',1000));}
  memoBoxes.add(MemoBox('상자',ids:[a.id]));final filters=ThoughtFilterSelection();
  await tester.pumpWidget(MaterialApp(home:AttachmentCollection(audio:audio,selector:const SizedBox(),filters:filters)));await tester.pump();await tester.pump(const Duration(milliseconds:300));
  final kind=audio?'음성':'사진';expect(find.text('$kind 2개'),findsOneWidget);expect(find.byType(ThoughtFilters),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('thought-filter-box-상자')));await tester.pump();await tester.pump(const Duration(milliseconds:300));expect(find.text('$kind 1개'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('thought-filter-tag-둘째')));await tester.pump();await tester.pump(const Duration(milliseconds:300));expect(find.text('$kind 2개'),findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('thought-filter-all')));await tester.pump();await tester.pump(const Duration(milliseconds:300));expect(filters.isEmpty,isTrue);
  await tester.pumpWidget(const SizedBox());filters.dispose();
 });}
 testWidgets('memo box canvas preserves legacy layout data',(tester)async{
  final r=elements.add('생각');pageGraphLayout.positions[r.id]=const Offset(123,456);
  await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[],initialView:ThoughtView.page)));await tester.pump();await tester.pump(const Duration(milliseconds:300));
  expect(find.text('다이어그램'),findsNothing);expect(activeThoughtViews,hasLength(7));
  expect(find.byType(ThoughtPage),findsOneWidget);
  expect(pageGraphLayout.positions[r.id],const Offset(123,456));
  await tester.pumpWidget(const SizedBox());
 });
}

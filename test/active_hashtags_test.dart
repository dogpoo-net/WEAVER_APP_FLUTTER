import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/tag_colors.dart';
import 'package:weaver/features/inbox/tag_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/main.dart';

void main(){
 setUp((){elements.clear();hashtagColors.clear();SharedPreferences.setMockInitialValues({});});
 testWidgets('orphan tag metadata is hidden and trashed tags return on restore',(tester)async{
 final r=elements.add('자료 #테스트');hashtagColors['테스트']=0xFF123456;hashtagColors['빈태그']=0xFF654321;
 await tester.pumpWidget(const MaterialApp(home:AllThoughtsPage(notes:[])));await tester.pumpAndSettle();
 expect(find.byKey(const ValueKey('thought-filter-tag-테스트')),findsOneWidget);
 expect(find.byKey(const ValueKey('thought-filter-tag-빈태그')),findsNothing);
 elements.remove(r.text);await tester.pumpAndSettle();
 expect(find.byKey(const ValueKey('thought-filter-tag-테스트')),findsNothing);
 expect(elements.trash[r.id]!.tags,contains('테스트'));
 final restored=elements.trash.remove(r.id)!;restored.deletedAt=null;elements.records[restored.text]=restored;elements.refreshVisibility();
 await tester.pumpAndSettle();
 expect(find.byKey(const ValueKey('thought-filter-tag-테스트')),findsOneWidget);
 expect(hashtagColors['테스트'],0xFF123456);
 await tester.pumpWidget(const SizedBox());
 });
 testWidgets('menu does not treat color-only tags as existing content',(tester)async{
 elements.add('내용 #사용중');hashtagColors['비어있음']=0xFF123456;
 SharedPreferences.setMockInitialValues({WorkspaceStorage.key:WorkspaceSnapshot.encode([])});
 final storage=WorkspaceStorage(await SharedPreferences.getInstance());
 await tester.pumpWidget(MyApp(requireLogin:false,storage:storage));await tester.pumpAndSettle();
 await tester.tap(find.byTooltip('메뉴 열기'));await tester.pumpAndSettle();
 final menu=tester.widget<WorkspaceMenu>(find.byType(WorkspaceMenu));
 expect(menu.tags,contains('사용중'));expect(menu.tags,isNot(contains('비어있음')));
 await tester.pumpWidget(const SizedBox());
 });
 testWidgets('tag detail has no tag-level hide control',(tester)async{
 elements.add('내용 #자료');
 await tester.pumpWidget(MaterialApp(home:TagPage(tag:'자료',notes:const [],onOpen:(_)async{})));
 expect(find.text('이 태그의 생각 검색 숨기기'),findsNothing);
 expect(find.byType(SwitchListTile),findsNothing);
 await tester.pumpWidget(const SizedBox());
 });
}

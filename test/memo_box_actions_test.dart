import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_box_actions.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_filters.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  setUp(() { memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear(); });
  testWidgets('Deleting a box permanently removes its thoughts while deleting a folder preserves them', (tester) async {
    SharedPreferences.setMockInitialValues({});elements.clear();
    final record=elements.add('보관된 메모');final box=MemoBox('상자',folder:'폴더',ids:[record.id]);memoBoxes.add(box);memoBoxFolders.add('폴더');
    final storage=WorkspaceStorage(await SharedPreferences.getInstance());await storage.write(WorkspaceSnapshot.encode([]));
    var deleted=0,folders=0;storage.syncDeleted=()async{deleted++;};storage.syncFolders=()async{folders++;};
    await tester.pumpWidget(MaterialApp(home:InboxPage(storage:storage,themeMode:ThemeMode.light,onThemeChanged:(_){})));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메뉴 열기'));await tester.pumpAndSettle();await tester.ensureVisible(find.byTooltip('폴더 폴더 관리'));await tester.tap(find.byTooltip('폴더 폴더 관리'));await tester.pumpAndSettle();await tester.tap(find.text('폴더 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();
    expect(folders,1);expect(memoBoxFolders,isEmpty);expect(memoBoxes.firstWhere((b)=>b.name=='상자').folder,isNull);expect(elements.records,contains('보관된 메모'));
    await tester.tap(find.byTooltip('메뉴 닫기'));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('thoughts-all')));await tester.pumpAndSettle();await tester.tap(find.text('메모상자').last);await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-filter-box-상자')));await tester.pumpAndSettle();await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();await tester.tap(find.text('메모상자 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();
    expect(deleted,1);expect(elements.records,isEmpty);expect(elements.trash,isEmpty);expect(memoBoxes.any((b)=>b.name=='상자'),isFalse);
    expect(WorkspaceSnapshot.decode(storage.read()!).records,isEmpty);await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Box deletion requires selection and two confirmations; cancel changes nothing', (tester) async {
    final box=MemoBox('삭제 대상');memoBoxes.add(box);ensureUnclassifiedBox();final filters=ThoughtFilterSelection(initialBox:box);Set<String>? deleted;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:MemoBoxActions(filters:filters,onCreate:(){},onDelete:(names)async{deleted=names;}))));
    await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();await tester.tap(find.text('메모상자 삭제'));await tester.pumpAndSettle();
    expect(deleted,isNull);expect(find.text('삭제 대상'),findsOneWidget);
    await tester.tap(find.text('삭제'));await tester.pumpAndSettle();expect(find.text('정말 삭제하시겠습니까?'),findsOneWidget);expect(find.textContaining('포함된 메모는 전부 사라지고'),findsOneWidget);
    await tester.tap(find.text('취소'));await tester.pumpAndSettle();expect(deleted,isNull);
    await tester.tap(find.byTooltip('메모상자 관리'));await tester.pumpAndSettle();await tester.tap(find.text('메모상자 삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();await tester.tap(find.text('삭제'));await tester.pumpAndSettle();expect(deleted,{'삭제 대상'});
    await tester.pumpWidget(const SizedBox());filters.dispose();
  });
  testWidgets('Opening overview and selecting another tab requests fresh server changes', (tester) async {
    var reads=0;await tester.pumpWidget(MaterialApp(home:AllThoughtsPage(notes:[],onRefresh:()async{reads++;})));
    await tester.pumpAndSettle();expect(reads,1);await tester.tap(find.text('문서'));await tester.pumpAndSettle();expect(reads,2);
    await tester.tap(find.text('생각'));await tester.pumpAndSettle();expect(reads,3);await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Folder deletion confirms preservation and invokes its category', (tester) async {
    String? removed;await tester.pumpWidget(MaterialApp(home:Scaffold(body:WorkspaceMenu(embedded:true,projects:[],folders:['폴더'],onDeleteFolder:(kind,folder)async{removed='$kind/$folder';}))));
    await tester.tap(find.byTooltip('폴더 폴더 관리'));await tester.pumpAndSettle();await tester.tap(find.text('폴더 삭제'));await tester.pumpAndSettle();
    expect(find.textContaining('자료는 삭제하지 않습니다.'),findsOneWidget);await tester.tap(find.text('삭제'));await tester.pumpAndSettle();expect(removed,'project/폴더');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/limited_rows_wrap.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';

void main() {
  testWidgets('badge layout uses five actual rows', (tester) async {
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Center(child: SizedBox(width: 200,
      child: ClipRect(child: LimitedRowsWrap(children: [for (var i = 0; i < 20; i++) const SizedBox(width: 90, height: 30)]))))));
    expect(tester.getSize(find.byType(LimitedRowsWrap)).height, 174);
    expect(tester.takeException(), isNull);
  });
  testWidgets('badge more appends rows while all opens the full page', (tester) async {
    elements.clear();
    for (var i = 0; i < 22; i++) { elements.add('테스트 메모 내용이 길게 이어집니다 $i'); }
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    await tester.pumpWidget(MyApp(storage: WorkspaceStorage(await SharedPreferences.getInstance())));
    await tester.pumpAndSettle();
    final badges = find.byKey(const ValueKey('recent-memo-badges'));
    final before = tester.getSize(badges).height;
    final more = find.byKey(const ValueKey('thoughts-more'));
    await tester.ensureVisible(more); await tester.tap(more); await tester.pumpAndSettle();
    expect(tester.getSize(badges).height, greaterThan(before));
    expect(find.byType(AllThoughtsPage), findsNothing);
    final all = find.byKey(const ValueKey('thoughts-all'));
    await tester.ensureVisible(all); await tester.tap(all); await tester.pumpAndSettle();
    expect(find.byType(AllThoughtsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('main shows five newest paragraphs and projects but searches older entries', (tester) async {
    elements.clear();
    final notes = <Note>[];
    for (var i = 0; i < 7; i++) {
      notes.add(Note('문단$i', created: DateTime.utc(2026, 1, i + 1))..paragraphs = [Paragraph('문단$i', ParagraphRole.body)]);
      notes.add(Note('프로젝트$i', created: DateTime.utc(2026, 1, i + 1))..project = WritingProject(
        [Paragraph('본문$i', ParagraphRole.body)], [], name: '프로젝트$i'));
    }
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode(notes)});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage)); await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '문단0'), findsNothing);
    expect(find.widgetWithText(ListTile, '프로젝트0'), findsNothing);
    expect(find.text('문단6'), findsOneWidget);
    expect(find.text('프로젝트6'), findsOneWidget);
    final search = find.byKey(const ValueKey('note-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '문단0'); await tester.pumpAndSettle();
    expect(find.text('문단0'), findsOneWidget);
    await tester.enterText(search, '프로젝트0'); await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '프로젝트0'), findsOneWidget);
    await tester.enterText(search, ''); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('thoughts-all')));
    await tester.tap(find.byKey(const ValueKey('thoughts-all'))); await tester.pumpAndSettle();
    expect(find.byType(AllThoughtsPage), findsOneWidget);
  });
}

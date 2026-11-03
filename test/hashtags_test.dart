import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/tag_page.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/hashtags.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('tag results include matching paragraphs and projects only', (
    tester,
  ) async {
    elements.clear();
    elements.add('작은 생각 #독서');
    final paragraph = Note('작은 생각을 기록한다')
      ..paragraphs = [const Paragraph('작은 생각을 기록한다', ParagraphRole.body)];
    final project = Note('작은 생각을 모은다')
      ..paragraphs = [const Paragraph('작은 생각을 모은다', ParagraphRole.body)]
      ..project = WritingProject(
        [const Paragraph('작은 생각을 모은다', ParagraphRole.body)],
        [],
        name: '독서 프로젝트',
      );
    Note? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: TagPage(
          tag: '독서',
          notes: [
            paragraph,
            project,
            Note('관계없는 글')
              ..paragraphs = [const Paragraph('관계없는 글', ParagraphRole.body)],
          ],
          onOpen: (note) async {
            opened = note;
          },
        ),
      ),
    );
    expect(find.text('문단 1'), findsOneWidget);
    expect(find.text('프로젝트 1'), findsOneWidget);
    expect(find.text('관계없는 글'), findsNothing);
    await tester.tap(find.text('독서 프로젝트'));
    await tester.pump();
    expect(opened, same(project));
  });
  test('hashtags are normalized, deduplicated and survive JSON round trip', () {
    elements.clear();
    final parsed = parseTaggedInput('작은 생각 #독서 #Dart #dart');
    expect(parsed.text, '작은 생각');
    expect(parsed.tags, {'독서', 'dart'});
    expect(parseTaggedInput('C# 공부').text, 'C# 공부');
    final record = elements.add('작은 생각 #독서 #Dart');
    final snapshot = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
    snapshot.apply();
    expect(elements.records[record.text]!.tags, {'독서', 'dart'});
    expect(() => elements.add('#태그'), throwsArgumentError);
  });
  testWidgets('tag saved with element appears in menu and opens related list', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField).first, '작은 생각 #독서');
    await tester.pump();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('작은 생각'), findsOneWidget);
    expect(find.text('작은 생각 #독서'), findsNothing);
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    final tag = find.byKey(const ValueKey('menu-tag-0'));
    await tester.scrollUntilVisible(tag, 100, scrollable: find.descendant(
      of: find.byKey(const ValueKey('menu-projects')), matching: find.byType(Scrollable)));
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.text('원소 1'), findsOneWidget);
    expect(find.text('작은 생각'), findsOneWidget);
    expect(find.text('문단 0'), findsOneWidget);
    expect(find.text('프로젝트 0'), findsOneWidget);
  });
}

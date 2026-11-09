import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('project assistance links by title and saves reciprocal IDs', (tester) async {
    final a = WritingProject([], [], name: '현재')..document = '본문';
    final b = WritingProject([], [], name: 'Reference project')..document = '별도 내용';
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: ProjectDocumentEditor(project: a, projects: [a, b])));
    await tester.enterText(find.byKey(const ValueKey('project-document')), '본문 Reference');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('project-link-${b.id}')), findsOneWidget);
    expect(a.linkedProjectIds, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, '본문 ');
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(a.linkedProjectIds, {b.id}); expect(b.linkedProjectIds, {a.id});
    b.name = '새 이름';
    final saved = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([Note(a.content)..project = a, Note(b.content)..project = b]));
    expect(saved.notes.first.project!.linkedProjectIds, {saved.notes.last.project!.id});
    final chip = tester.widget<InputChip>(find.byKey(ValueKey('project-link-${b.id}')));
    chip.onDeleted!(); await tester.pump();
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(a.linkedProjectIds, isEmpty); expect(b.linkedProjectIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

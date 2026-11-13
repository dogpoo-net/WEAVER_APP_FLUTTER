import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/desktop_menu_frame.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/element_binding.dart';

void main() {
  testWidgets('project creation uses a single document', (tester) async {
    WritingProject? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await Navigator.push<WritingProject>(context, MaterialPageRoute(builder: (_) => const DesktopMenuFrame(child: ProjectDocumentEditor()))); }, child: const Text('시작'))))));
    await tester.tap(find.text('시작')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('project-document')), '첫 줄\n두 번째 줄');
    expect(find.text('다음 문단'), findsNothing);
    await tester.tap(find.byTooltip('저장')); await tester.pumpAndSettle();
    expect(result!.document, '첫 줄\n두 번째 줄');
    expect(result!.paragraphs, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('editing preserves original paragraph roles and bindings across storage', (tester) async {
    final original = Paragraph('원본', ParagraphRole.title, bindings: [const ElementBinding('source', 0, 2)]);
    final project = WritingProject([original], [], name: '보존');
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentEditor(project: project)));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, '======원본======');
    await tester.enterText(find.byKey(const ValueKey('project-document')), '새 통합 본문');
    await tester.tap(find.byTooltip('저장')); await tester.pumpAndSettle();
    final restored = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([Note(project.content)..project = project])).notes.single.project!;
    expect(restored.document, '새 통합 본문');
    expect(restored.paragraphs.single.text, '원본');
    expect(restored.paragraphs.single.role, ParagraphRole.title);
    expect(restored.paragraphs.single.bindings.single.id, 'source');
    expect(tester.takeException(), isNull);
  });
}

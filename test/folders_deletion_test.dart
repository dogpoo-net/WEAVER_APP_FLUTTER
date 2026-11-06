import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_folders.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(() {
    elements.clear();
    projectFolders.clear();
  });
  test(
    'folders and assignments survive backup; deleted words preserve text',
    () {
      elements.add('기억');
      projectFolders.addAll(['자료', '빈 폴더']);
      final project = WritingProject(
        [Paragraph('기억을 기록', ParagraphRole.body)],
        ['기억'],
        name: '기록',
        folder: '자료',
      );
      final note = Note('기억을 기록')..project = project;
      elements.remove('기억');
      final snapshot = WorkspaceSnapshot.decode(
        WorkspaceSnapshot.encode([note]),
      );
      snapshot.apply();
      expect(projectFolders, ['자료', '빈 폴더']);
      expect(snapshot.notes.single.project!.folder, '자료');
      expect(snapshot.notes.single.project!.paragraphs.single.text, '기억을 기록');
      expect(elements.words, isEmpty);
    },
  );
  testWidgets('metadata deletion requires confirmation', (tester) async {
    elements.add('기억');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showElementMetadata(context, '기억'),
              child: const Text('정보'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('정보'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('생각 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(elements.words, ['기억']);
    await tester.tap(find.text('생각 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(elements.words, isEmpty);
    expect(find.text('정보'), findsOneWidget);
  });
}

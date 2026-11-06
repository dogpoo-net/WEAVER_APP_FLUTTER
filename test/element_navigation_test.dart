import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  setUp(elements.clear);
  testWidgets('metadata no longer scans or navigates project usage', (
    tester,
  ) async {
    elements.add('기억');
    final project = WritingProject(
      [
        for (var i = 0; i < 25; i++) Paragraph('여백 문단 $i', ParagraphRole.body),
        const Paragraph('첫 기억. 두번째 기억을 담은 문장.', ParagraphRole.body),
      ],
      [],
      name: '프로젝트',
    );
    elements.indexProject(project);
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
    expect(find.text('프로젝트 사용'), findsNothing);
    expect(find.text('사용 위치'), findsNothing);
    expect(find.text('함께 쓰인 원소'), findsNothing);
    expect(find.byType(ProjectPage), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('element-editor'))).controller!.text, '기억');
    expect(tester.takeException(), isNull);
  });
}

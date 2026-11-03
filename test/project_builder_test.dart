import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_builder.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  testWidgets('one title, custom name and append order', (tester) async {
    WritingProject? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<WritingProject>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProjectBuilder(
                      available: [
                        Paragraph('제목 A', ParagraphRole.title),
                        Paragraph('제목 B', ParagraphRole.title),
                        Paragraph('내용 C', ParagraphRole.body),
                      ],
                      words: ['원소'],
                    ),
                  ),
                );
              },
              child: const Text('시작'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('본문'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('project-name')))
          .controller!
          .text,
      '제목 A',
    );
    await tester.tap(find.byKey(const ValueKey('pick-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('pick-1')))
          .value,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('project-name')),
      '내 프로젝트',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('프로젝트 만들기'));
    await tester.tap(find.text('프로젝트 만들기'));
    await tester.pumpAndSettle();
    expect(result!.name, '내 프로젝트');
    expect(result!.paragraphs.map((p) => p.text), ['내용 C', '제목 A']);
    expect(result!.words, ['원소']);
  });
}

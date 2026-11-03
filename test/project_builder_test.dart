import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_builder.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  testWidgets('project writes roles and loads an independent copy from a searchable modal', (tester) async {
    WritingProject? result;
    const source = Paragraph('저장된 원본 문단', ParagraphRole.body, tags: {'자료'});
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await Navigator.push<WritingProject>(context,
        MaterialPageRoute(builder: (_) => const ProjectBuilder(available: [source], words: ['원소']))); },
      child: const Text('시작'),
    )))));
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('project-name')), '새 프로젝트');
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '직접 쓴 제목');
    await tester.tap(find.text('제목'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음 문단'));
    await tester.tap(find.text('다음 문단'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('문단 찾기'));
    await tester.tap(find.text('문단 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '내용 또는 태그 검색'), '#자료');
    await tester.pumpAndSettle();
    expect(find.text('저장된 원본 문단'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('paragraph-1')), '프로젝트에서 수정한 문장');
    await tester.tap(find.text('프로젝트 만들기'));
    await tester.pumpAndSettle();
    expect(result!.name, '새 프로젝트');
    expect(result!.paragraphs.map((p) => p.text), ['직접 쓴 제목', '프로젝트에서 수정한 문장']);
    expect(result!.paragraphs.map((p) => p.role), [ParagraphRole.title, ParagraphRole.body]);
    expect(source.text, '저장된 원본 문단');
    expect(result!.words, ['원소']);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  testWidgets('project tabs show sentences before elements and open the corresponding content', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: WritingProject(
      const [Paragraph('프로젝트 문장', ParagraphRole.body)], [], name: '프로젝트'))));
    expect(tester.getCenter(find.widgetWithText(ChoiceChip, '문장')).dx,
      lessThan(tester.getCenter(find.widgetWithText(ChoiceChip, '원소')).dx));
    await tester.tap(find.widgetWithText(ChoiceChip, '문장'));
    await tester.pumpAndSettle();
    expect(find.text('프로젝트 문장'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '원소'));
    await tester.pumpAndSettle();
    expect(find.text('이 프로젝트에서 사용한 원소'), findsOneWidget);
  });

  testWidgets('handle drag moves text and role together and saves the new order', (tester) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Paragraph>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { saved = await Navigator.push<List<Paragraph>>(context,
        MaterialPageRoute(builder: (_) => const ParagraphEditor(projectEditing: true, words: [], initial: [
          Paragraph('첫 제목', ParagraphRole.title), Paragraph('두번째 본문', ParagraphRole.body), Paragraph('세번째 부제', ParagraphRole.subtitle),
        ]))); }, child: const Text('편집'),
    )))));
    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    final first = tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0'))).controller!;
    final handle = find.byKey(const ValueKey('reorder-paragraph-0'));
    final target = tester.getBottomLeft(find.byKey(const ValueKey('paragraph-2'))) + const Offset(24, 80);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await drag.moveTo(target);
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('paragraph-2'))).controller, same(first));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0'))).controller!.text, '두번째 본문');
    await tester.enterText(find.byKey(const ValueKey('paragraph-2')), '이동 후 제목');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(saved!.map((p) => p.text), ['두번째 본문', '세번째 부제', '이동 후 제목']);
    expect(saved!.map((p) => p.role), [ParagraphRole.body, ParagraphRole.subtitle, ParagraphRole.title]);
    expect(tester.takeException(), isNull);
  });
}

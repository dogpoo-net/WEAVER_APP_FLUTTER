import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_footnote_dialog.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  testWidgets(
    'mobile footnote input wraps in a wide dialog and submits on Done',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? added;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDocumentFootnotes(
                  context,
                  notes: {},
                  onAdd: (text) {
                    added = text;
                    return 'note-1';
                  },
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('각주 추가'));
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, '각주 내용');
      expect(tester.getSize(input).width, greaterThanOrEqualTo(300));
      expect(tester.widget<TextField>(input).minLines, 3);
      await tester.enterText(input, '여러 줄 높이로 표시되는 긴 각주\n다음 내용');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(added, '여러 줄 높이로 표시되는 긴 각주 다음 내용');
    },
  );

  testWidgets('manage and reuse a footnote at the rich editor caret', (
    tester,
  ) async {
    final project = WritingProject([], [], name: '문서')
      ..document = '======문서======\n앞 **가운데** 뒤';
    await tester.pumpWidget(
      MaterialApp(home: ProjectDocumentEditor(project: project)),
    );
    await tester.tap(find.text('서식 편집'));
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final plain = editor.controller.document.toPlainText();
    editor.controller.updateSelection(
      TextSelection.collapsed(offset: plain.indexOf('가운데') + 1),
      quill.ChangeSource.local,
    );
    await tester.ensureVisible(find.byTooltip('각주 관리'));
    await tester.tap(find.byTooltip('각주 관리'));
    await tester.pumpAndSettle();
    expect(find.text('아직 각주가 없습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('각주 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '각주 내용'), '참고 내용');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('참고 내용'), findsOneWidget);
    await tester.tap(find.text('삽입'));
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(find.text('[1]'), findsOneWidget);
    expect(find.text('[^note-1]'), findsNothing);
    expect(find.text('[^note-1]: 참고 내용'), findsNothing);
    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(find.text('[1]'), findsOneWidget);
    expect(project.content, contains('[^note-1]: 참고 내용'));

    await tester.tap(find.text('원문 편집'));
    await tester.pumpAndSettle();
    final source = tester
        .widget<TextField>(find.byKey(const ValueKey('project-document')))
        .controller!;
    expect(source.text, contains('**가[^note-1]운데**'));
    expect(source.text, contains('[^note-1]: 참고 내용'));

    source.selection = TextSelection.collapsed(
      offset: source.text.indexOf('앞 '),
    );
    await tester.ensureVisible(find.byTooltip('각주 관리'));
    await tester.tap(find.byTooltip('각주 관리'));
    await tester.pumpAndSettle();
    expect(find.text('참고 내용'), findsOneWidget);
    await tester.tap(find.text('삽입'));
    await tester.pumpAndSettle();
    expect(source.text, contains('\n[^note-1]앞 '));
    expect(RegExp(r'\[\^note-1\]:').allMatches(source.text), hasLength(1));
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_markup.dart';
import 'package:weaver/features/inbox/document_rich_editor.dart';
import 'package:weaver/features/inbox/document_syntax.dart';
import 'package:weaver/features/inbox/document_visual_block.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  testWidgets('visual blocks can be aligned from hover or tap', (tester) async {
    var source = '본문\n-----\n<photo id="photo-1">\n끝';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentRichEditor(
            source: source,
            links: const [],
            onPatch: (start, end, replacement) =>
                source = source.replaceRange(start, end, replacement),
            onLinkHover: (_) {},
            onInsertFootnote: null,
            onInsertTable: null,
            modeSwitch: const SizedBox(),
            dirty: false,
            diagnostics: const [],
            onSyntaxDiagnostic: (_, _, {touch = false}) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final divider = find.byType(DocumentVisualBlockView).first;
    final originalPhotoTop = tester
        .getTopLeft(find.byType(DocumentVisualBlockView).last)
        .dy;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(divider));
    await tester.pump();
    final center = find.byTooltip('구분선 가운데 정렬');
    expect(
      tester.getTopLeft(find.byType(DocumentVisualBlockView).last).dy,
      originalPhotoTop,
    );
    expect(
      tester.getCenter(center).dy,
      greaterThan(tester.getBottomLeft(divider).dy),
    );
    await mouse.moveTo(tester.getCenter(center));
    await tester.pump();
    await tester.tap(center);
    await tester.pump();
    expect(source, contains('| ----- |'));
    await tester.tap(find.byTooltip('구분선 너비 늘리기'));
    await tester.pump();
    expect(source, contains('| ----- {width=70%} |'));
    await mouse.removePointer();
    await tester.pump();
    expect(center, findsNothing);

    final photo = find.byType(DocumentVisualBlockView).last;
    await tester.tap(photo);
    await tester.pump();
    await tester.tap(find.byTooltip('사진 오른쪽 정렬'));
    await tester.pump();
    expect(source, contains('| <photo id="photo-1">|'));
    await tester.tap(find.byTooltip('사진 너비 줄이기'));
    await tester.pump();
    expect(source, contains('| <photo id="photo-1" width="90%">|'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocumentMarkup(text: source)),
      ),
    );
    await tester.pump();
    final blocks = tester
        .widgetList<DocumentVisualBlockView>(
          find.byType(DocumentVisualBlockView),
        )
        .toList();
    expect(blocks[0].block.alignment, DocumentBlockAlignment.center);
    expect(blocks[1].block.alignment, DocumentBlockAlignment.right);
    expect(blocks.map((view) => view.block.widthPercent), [70, 90]);
  });

  testWidgets(
    'selected visual blocks can be deleted with keyboard or toolbar',
    (tester) async {
      var source = '본문\n-----\n-----\n-----\n끝';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentRichEditor(
              source: source,
              links: const [],
              onPatch: (start, end, replacement) =>
                  source = source.replaceRange(start, end, replacement),
              onLinkHover: (_) {},
              onInsertFootnote: null,
              onInsertTable: null,
              modeSwitch: const SizedBox(),
              dirty: false,
              diagnostics: const [],
              onSyntaxDiagnostic: (_, _, {touch = false}) {},
            ),
          ),
        ),
      );
      for (final key in [
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.delete,
      ]) {
        await tester.tap(find.byType(DocumentVisualBlockView).first);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(find.byType(DocumentVisualBlockView), findsOneWidget);
      await tester.tap(find.byType(DocumentVisualBlockView));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('구분선 삭제'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentVisualBlockView), findsNothing);
      expect(source, startsWith('본문\n'));
      expect(source, endsWith('\n끝'));
      expect(source, isNot(contains('-----')));
    },
  );

  testWidgets('the rich toolbar adds a five-hyphen divider to source', (
    tester,
  ) async {
    final project = WritingProject([], [], name: '문서')..document = '본문';
    await tester.pumpWidget(
      MaterialApp(home: ProjectDocumentEditor(project: project)),
    );
    await tester.tap(find.text('서식 편집'));
    await tester.pumpAndSettle();
    final button = find.byTooltip('구분선 삽입');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentVisualBlockView), findsOneWidget);
    await tester.tap(find.text('원문 편집'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('project-document')),
    );
    expect(field.controller!.text, '본문\n-----\n');
  });
}

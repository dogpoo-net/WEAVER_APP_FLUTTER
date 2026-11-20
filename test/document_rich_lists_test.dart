import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_rich_editor.dart';
import 'package:weaver/features/inbox/document_markup.dart';

void main() {
  for (final (marker, style) in [('1.', 'ordered'), ('-', 'bullet')]) {
    testWidgets('$marker waits for space before becoming a list', (
      tester,
    ) async {
      var source = '';
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
      final controller = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        marker,
        TextSelection.collapsed(offset: marker.length),
      );
      expect(controller.document.toPlainText(), '$marker\n');
      controller.replaceText(
        marker.length,
        0,
        ' ',
        TextSelection.collapsed(offset: marker.length + 1),
      );
      await tester.pump();
      expect(controller.document.toPlainText(), '\n');
      expect(controller.getSelectionStyle().attributes['list']?.value, style);
      expect(source, '$marker ');

      await tester.ensureVisible(find.byTooltip('글머리표'));
      await tester.tap(find.byTooltip('글머리표'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('-').last);
      await tester.pumpAndSettle();
      expect(source, '– ');
      expect(controller.getSelectionStyle().attributes['list']?.value, 'dash');
      expect(find.text('-'), findsOneWidget);
    });
  }

  testWidgets('document reader renders both bullet styles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DocumentMarkup(text: '- 점\n– 대시\n-공백 없음')),
      ),
    );
    expect(find.text('•'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('-공백 없음', findRichText: true), findsOneWidget);
  });
}

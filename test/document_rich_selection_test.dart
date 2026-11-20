import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_rich_editor.dart';
import 'package:weaver/features/inbox/element_binding.dart';

void main() {
  testWidgets('heading, linked text and multiline code use one selection', (
    tester,
  ) async {
    const source =
        '======Title======\nLinked memo\n<code lang="dart">\nprint(1);\n</code>\nLast line';
    final start = source.indexOf('Linked memo');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentRichEditor(
            source: source,
            links: [
              ElementBinding('label:1', start, start + 'Linked memo'.length),
            ],
            onPatch: (_, _, _) {},
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
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final plain = editor.controller.document.toPlainText();
    expect(plain, startsWith('Title\nLinked memo\n'));
    expect(plain, contains('print(1);'));
    expect(plain, endsWith('Last line\n'));
    editor.controller.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.indexOf('Last line')),
      quill.ChangeSource.local,
    );
    expect(
      editor.controller.selection.textInside(plain),
      contains('print(1);'),
    );
  });
}

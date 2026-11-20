import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_line_shortcuts.dart';
import 'package:weaver/features/inbox/document_syntax.dart';

void main() {
  test('line commands act on whole selected lines and keep the selection', () {
    const source = 'one\ntwo\nthree\nfour';
    const selection = TextSelection(baseOffset: 5, extentOffset: 13);
    void check(
      DocumentLineAction action,
      String expected,
      TextSelection caret,
    ) {
      final edit = editDocumentLines(source, selection, action)!;
      expect(
        source.replaceRange(edit.start, edit.end, edit.replacement),
        expected,
      );
      expect(edit.selection, caret);
    }

    check(
      DocumentLineAction.comment,
      'one\n<!--two\nthree-->\nfour',
      const TextSelection(baseOffset: 9, extentOffset: 17),
    );
    check(
      DocumentLineAction.delete,
      'one\nfour',
      const TextSelection.collapsed(offset: 4),
    );
    check(
      DocumentLineAction.moveUp,
      'two\nthree\none\nfour',
      const TextSelection(baseOffset: 1, extentOffset: 9),
    );
    check(
      DocumentLineAction.moveDown,
      'one\nfour\ntwo\nthree',
      const TextSelection(baseOffset: 10, extentOffset: 18),
    );
    check(
      DocumentLineAction.copyUp,
      'one\ntwo\nthree\ntwo\nthree\nfour',
      selection,
    );
    check(
      DocumentLineAction.copyDown,
      'one\ntwo\nthree\ntwo\nthree\nfour',
      const TextSelection(baseOffset: 15, extentOffset: 23),
    );
  });

  test('HTML comments retain italic text and leave code examples intact', () {
    const source =
        '//italic//\n<!--alpha\nbeta-->\n<code><!--shown--></code>\nlast';
    final comments = DocumentComments(source);
    expect(comments.visibleText, '//italic//\n<code><!--shown--></code>\nlast');
    expect(comments.maskedText.length, source.length);
    final edit = editDocumentLines(
      '<!--hidden-->',
      const TextSelection.collapsed(offset: 7),
      DocumentLineAction.comment,
    )!;
    expect(edit.replacement, 'hidden');
  });
}

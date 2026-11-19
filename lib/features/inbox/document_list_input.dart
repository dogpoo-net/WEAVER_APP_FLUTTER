import 'package:flutter/services.dart';

import 'document_syntax.dart';

/// Continue a list on Enter without intercepting an active IME composition.
class DocumentListInput extends TextInputFormatter {
  const DocumentListInput();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!oldValue.selection.isValid || !oldValue.selection.isCollapsed ||
        !oldValue.composing.isCollapsed || !newValue.composing.isCollapsed) return newValue;
    final caret = oldValue.selection.extentOffset;
    final text = oldValue.text;
    if (newValue.text.length != text.length + 1 ||
        newValue.selection.extentOffset != caret + 1 ||
        newValue.text != text.replaceRange(caret, caret, '\n')) return newValue;
    final start = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final line = text.substring(start, caret);
    final marker = documentListMarker.firstMatch(line);
    if (marker == null || caretInsideCode(text, caret)) return newValue;
    final indent = marker.group(1)!;
    if (line.substring(marker.end).trim().isEmpty) {
      // Exit an empty list item with one Enter.
      return TextEditingValue(
        text: text.replaceRange(start, caret, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    final number = int.tryParse(marker.group(2) ?? '');
    final prefix = number == null ? '$indent- ' : '$indent${number + 1}. ';
    return TextEditingValue(
      text: newValue.text.replaceRange(caret + 1, caret + 1, prefix),
      selection: TextSelection.collapsed(offset: caret + 1 + prefix.length),
    );
  }
}

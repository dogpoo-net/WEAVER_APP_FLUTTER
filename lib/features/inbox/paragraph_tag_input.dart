import 'package:flutter/services.dart';

/// Keep separators ready for the next hashtag without changing IME composition.
class HashtagInputFormatter extends TextInputFormatter {
  const HashtagInputFormatter();

  String _normalize(String text) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)
        .map((t) => '#${t.replaceFirst(RegExp(r'^#+'), '')}').toList();
    if (RegExp(r'\s$').hasMatch(text) && (tokens.isEmpty || tokens.last != '#')) {
      tokens.add('#');
    }
    return tokens.join(' ');
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;
    if (oldValue.text.endsWith(' #') && newValue.text == oldValue.text.substring(0, oldValue.text.length - 1)) {
      final text = newValue.text.trimRight();
      return newValue.copyWith(text: text, selection: TextSelection.collapsed(offset: text.length), composing: TextRange.empty);
    }
    final text = _normalize(newValue.text);
    int offset(int original) {
      if (original < 0) return text.length;
      final prefix = newValue.text.substring(0, original.clamp(0, newValue.text.length));
      var result = _normalize(prefix).length;
      if (RegExp(r'\s$').hasMatch(prefix) && original < newValue.text.length && newValue.text[original] == '#') {
        result--;
      }
      return result.clamp(0, text.length);
    }
    return newValue.copyWith(text: text, selection: TextSelection(
      baseOffset: offset(newValue.selection.baseOffset),
      extentOffset: offset(newValue.selection.extentOffset),
      affinity: newValue.selection.affinity,
      isDirectional: newValue.selection.isDirectional,
    ), composing: TextRange.empty);
  }
}

class CompletedParagraphTags {
  const CompletedParagraphTags(this.value, this.tags);
  final TextEditingValue value;
  final Set<String> tags;
}

/// Extract only space-terminated hashtag tokens, preserving prose and caret.
CompletedParagraphTags takeCompletedParagraphTags(TextEditingValue value) {
  if (value.composing.isValid && !value.composing.isCollapsed) {
    return CompletedParagraphTags(value, const {});
  }
  final ranges = <TextRange>[];
  final tags = <String>{};
  final pattern = RegExp(r'(^|\s)#([^\s#.,!?;:،؛؟()\[\]{}]+)(?=\s)', multiLine: true);
  for (final match in pattern.allMatches(value.text)) {
    tags.add(match.group(2)!.toLowerCase());
    var end = match.end;
    if (end < value.text.length && (value.text[end] == ' ' || value.text[end] == '\t')) end++;
    ranges.add(TextRange(start: match.start + match.group(1)!.length, end: end));
  }
  if (ranges.isEmpty) return CompletedParagraphTags(value, tags);
  var text = value.text;
  for (final range in ranges.reversed) {
    text = text.replaceRange(range.start, range.end, '');
  }
  int offset(int original) {
    if (original < 0) return text.length;
    var removed = 0;
    for (final range in ranges) {
      removed += (original - range.start).clamp(0, range.end - range.start);
    }
    return (original - removed).clamp(0, text.length);
  }
  return CompletedParagraphTags(value.copyWith(text: text, selection: TextSelection(
    baseOffset: offset(value.selection.baseOffset), extentOffset: offset(value.selection.extentOffset),
    affinity: value.selection.affinity, isDirectional: value.selection.isDirectional,
  ), composing: TextRange.empty), tags);
}

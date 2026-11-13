import 'package:flutter/services.dart';

class CompletedParagraphTags {
  const CompletedParagraphTags(this.value, this.tags, [this.removed = const []]);
  final List<TextRange> removed;
  final TextEditingValue value;
  final Set<String> tags;
}

/// Extract only space-terminated hashtag tokens, preserving prose and caret.
CompletedParagraphTags takeCompletedParagraphTags(TextEditingValue value, {Iterable<TextRange> protected = const [], bool consumeLineBreak = false}) {
  if (value.composing.isValid && !value.composing.isCollapsed) {
    return CompletedParagraphTags(value, const {});
  }
  final ranges = <TextRange>[];
  final tags = <String>{};
  final pattern = RegExp(r'(^|\s)#([^\s#.,!?;:،؛؟()\[\]{}]+)(?=\s)', multiLine: true);
  for (final match in pattern.allMatches(value.text)) {
    if (protected.any((range) => range.start < match.end && range.end > match.start)) continue;
    tags.add(match.group(2)!.toLowerCase());
    var end = match.end;
    if (end < value.text.length && (value.text[end] == ' ' || value.text[end] == '\t')) { end++; }
    else if (consumeLineBreak && value.text.startsWith('\r\n', end)) { end += 2; }
    else if (consumeLineBreak && end < value.text.length && value.text[end] == '\n') { end++; }
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
  ), composing: TextRange.empty), tags, ranges);
}

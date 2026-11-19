/// Equals delimiters are syntax; whitespace inside them is content.
final projectHeading = RegExp(r'^(={2,6})(?![=])(.+?)(?<![=])\1$');
final codeMarkup = RegExp(r'<code>[\s\S]*?(?:</code>|$)');

bool caretInsideCode(String text, int caret) => codeMarkup.allMatches(text).any((match) =>
  caret > match.start && (caret < match.end || (caret == match.end && !match.group(0)!.endsWith('</code>'))));

String documentTitle(String text) {
  final prose = text.replaceAllMapped(codeMarkup, (match) => '\n' * '\n'.allMatches(match.group(0)!).length);
  for (final line in prose.split('\n')) {
    final heading = projectHeading.firstMatch(line);
    if (heading != null) return heading.group(2)!.trim();
  }
  return prose.split('\n').where((line) => !documentEditorComment.hasMatch(line) && !documentFootnoteDefinition.hasMatch(line)).map((s) => s.trim()).where((s) => s.isNotEmpty).firstOrNull ?? '문서';
}

final documentFootnoteDefinition = RegExp(r'^\[\^([a-zA-Z0-9_-]+)\]:[ \t]+(.+)$');
final documentFootnoteReference = RegExp(r'\[\^([a-zA-Z0-9_-]+)\]');
final documentEditorComment = RegExp(r'^\s*<!--.*-->\s*$');

final documentListMarker = RegExp(r'^([ \t]*)(?:(\d{1,9})\.|-)[ \t]+');

/// Closed code spans occupying complete lines can be rendered as blocks.
Iterable<RegExpMatch> documentCodeBlocks(String source) =>
    codeMarkup.allMatches(source).where((match) =>
      match.group(0)!.endsWith('</code>') &&
      (match.start == 0 || source[match.start - 1] == '\n') &&
      (match.end == source.length || source[match.end] == '\n'));

String documentCodeBody(String markup) {
  var body = markup.substring(6, markup.length - 7);
  if (body.startsWith('\n')) body = body.substring(1);
  if (body.endsWith('\n')) body = body.substring(0, body.length - 1);
  return body;
}

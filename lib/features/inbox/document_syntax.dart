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
  return prose.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).firstOrNull ?? '문서';
}

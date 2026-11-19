/// Equals delimiters are syntax; whitespace inside them is content.
final projectHeading = RegExp(r'^(={2,6})(?![=])(.+?)(?<![=])\1$');
final documentCodeOpening = RegExp(r'''<code(?:[ 	]+lang[ 	]*=[ 	]*(?:"([^"<>
]*)"|'([^'<>
]*)'|([^\s"'<>]+)))?[ 	]*>''');
final codeMarkup = RegExp(
  '${documentCodeOpening.pattern}'
  r'[\s\S]*?(?:</code>|$)',
);

String? documentCodeLanguage(String markup) {
  final open = documentCodeOpening.matchAsPrefix(markup);
  final language = (open?.group(1) ?? open?.group(2) ?? open?.group(3))?.trim();
  return language == null || language.isEmpty ? null : language;
}

bool caretInsideCode(String text, int caret) => codeMarkup
    .allMatches(text)
    .any(
      (match) =>
          caret > match.start &&
          (caret < match.end ||
              (caret == match.end && !match.group(0)!.endsWith('</code>'))),
    );

String documentTitle(String text) {
  final prose = text.replaceAllMapped(
    codeMarkup,
    (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
  );
  final lines = prose.split('\n');
  String? fallbackHeading;
  for (final line in lines) {
    final heading = projectHeading.firstMatch(line);
    if (heading == null) continue;
    final title = heading.group(2)!.trim();
    if (title.isEmpty) continue;
    if (heading.group(1)!.length == 6) return title;
    fallbackHeading ??= title;
  }
  return fallbackHeading ??
      lines
          .where(
            (line) =>
                !documentEditorComment.hasMatch(line) &&
                !documentFootnoteDefinition.hasMatch(line),
          )
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .firstOrNull ??
      '문서';
}

/// Heading 1 is the title; sections start at heading 2.
class DocumentHeadingNumbers {
  final _counters = List<int>.filled(4, 0);

  String next(int delimiterLength) {
    if (delimiterLength == 6) return '';
    final depth = 5 - delimiterLength;
    for (var i = 0; i < depth; i++) {
      if (_counters[i] == 0) _counters[i] = 1;
    }
    _counters[depth]++;
    for (var i = depth + 1; i < _counters.length; i++) {
      _counters[i] = 0;
    }
    return '${_counters.take(depth + 1).join('.')} ';
  }
}

final documentFootnoteDefinition = RegExp(
  r'^\[\^([a-zA-Z0-9_-]+)\]:[ \t]+(.+)$',
);
final documentFootnoteReference = RegExp(r'\[\^([a-zA-Z0-9_-]+)\]');
final documentEditorComment = RegExp(r'^\s*<!--.*-->\s*$');

final documentListMarker = RegExp(r'^([ \t]*)(?:(\d{1,9})\.|-)[ \t]+');

/// Closed code spans occupying complete lines can be rendered as blocks.
Iterable<RegExpMatch> documentCodeBlocks(String source) => codeMarkup
    .allMatches(source)
    .where(
      (match) =>
          match.group(0)!.endsWith('</code>') &&
          (match.start == 0 || source[match.start - 1] == '\n') &&
          (match.end == source.length || source[match.end] == '\n'),
    );

String documentCodeBody(String markup) {
  var body = markup.substring(
    documentCodeOpening.matchAsPrefix(markup)!.end,
    markup.length - 7,
  );
  if (body.startsWith('\n')) body = body.substring(1);
  if (body.endsWith('\n')) body = body.substring(0, body.length - 1);
  return body;
}

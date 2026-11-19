/// Equals delimiters are syntax; whitespace inside them is content.
final projectHeading = RegExp(r'^(={2,6})(?![=])(.+?)(?<![=])\1$');
final documentCodeOpening = RegExp(
  r'''<code(?:[ \t]+lang[ \t]*=[ \t]*(?:"([^"<>\r\n]*)"|'([^'<>\r\n]*)'|([^\s"'<>]+)))?[ \t]*>''',
);
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
  final prose = DocumentComments(text).visibleText.replaceAllMapped(
    codeMarkup,
    (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
  );
  final lines = prose.split('\n');
  String? fallbackHeading;
  for (final line in lines) {
    final heading = projectHeading.firstMatch(line.trimRight());
    if (heading == null) continue;
    final title = heading.group(2)!.trim();
    if (title.isEmpty) continue;
    if (heading.group(1)!.length == 6) return title;
    fallbackHeading ??= title;
  }
  return fallbackHeading ??
      lines
          .where((line) => !documentFootnoteDefinition.hasMatch(line))
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
// A paired, non-space-prefixed // span remains the existing italic markup.
final _documentTokens = RegExp(
  '${codeMarkup.pattern.replaceFirst(r'|$', r'|(?![\s\S])')}|'
  r'\[\[[^\r\n]*?\]\]|\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>\[\]]+|'
  r'//[^/\s][^\r\n]*?//|(?<comment>/\*[\s\S]*?(?:\*/|(?![\s\S]))|'
  r'^[ \t]*<!--[^\r\n]*-->[ \t]*(?=\r?$)|//[^\r\n]*)',
  multiLine: true,
);

class DocumentComments {
  DocumentComments(this.source);

  final String source;
  late final List<RegExpMatch> ranges = [
    for (final token in _documentTokens.allMatches(source))
      if (token.namedGroup('comment') != null) token,
  ];
  late final String visibleText = _visibleText();
  late final String maskedText = source.replaceAllMapped(_documentTokens, (
    token,
  ) {
    if (token.namedGroup('comment') == null) return token.group(0)!;
    return token.group(0)!.replaceAll(RegExp(r'[^\r\n]'), ' ');
  });

  late final List<({int start, int end})> removals = [
    for (final range in ranges) _removal(range),
  ];

  ({int start, int end}) _removal(RegExpMatch range) {
    final lineStart = range.start == 0
        ? 0
        : source.lastIndexOf('\n', range.start - 1) + 1;
    final nextLine = source.indexOf('\n', range.end);
    final lineEnd = nextLine < 0 ? source.length : nextLine;
    if (source.substring(lineStart, range.start).trim().isEmpty &&
        source.substring(range.end, lineEnd).trim().isEmpty) {
      return (start: lineStart, end: nextLine < 0 ? lineEnd : lineEnd + 1);
    }
    return (start: range.start, end: range.end);
  }

  String _visibleText() {
    if (ranges.isEmpty) return source;
    final buffer = StringBuffer();
    var start = 0;
    for (final range in removals) {
      buffer.write(source.substring(start, range.start));
      start = range.end;
    }
    buffer.write(source.substring(start));
    return buffer.toString();
  }
}

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

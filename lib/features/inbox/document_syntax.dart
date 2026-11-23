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
          .where(
            (line) =>
                !documentFootnoteDefinition.hasMatch(line) &&
                parseDocumentVisualBlock(line) == null,
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
final documentPhoto = RegExp(
  r'^<photo id="([a-zA-Z0-9_-]+)"(?: width="(\d{1,3})%")?>$',
);
const documentDivider = '-----';
final _sizedDivider = RegExp(r'^-----(\d{1,3})-----$');
final _legacySizedDivider = RegExp(r'^----- \{width[=:](\d{1,3})%\}$');

enum DocumentBlockAlignment { left, center, right }

typedef DocumentVisualBlock = ({
  String markup,
  String? photoId,
  int widthPercent,
  DocumentBlockAlignment alignment,
});

DocumentVisualBlock? parseDocumentVisualBlock(String line) {
  final wrapped = line.length > 2 && line.startsWith('|') && line.endsWith('|');
  final inner = wrapped ? line.substring(1, line.length - 1) : line;
  final markup = inner.trim();
  final photo = documentPhoto.firstMatch(markup);
  final sizedDivider = _sizedDivider.firstMatch(markup) ?? _legacySizedDivider.firstMatch(markup);
  if (photo == null && markup != documentDivider && sizedDivider == null)
    return null;
  final defaultWidth = photo == null ? 60 : 100;
  final width = int.tryParse(photo?.group(2) ?? sizedDivider?.group(1) ?? '');

  final alignment = !wrapped || !inner.startsWith(' ')
      ? DocumentBlockAlignment.left
      : inner.endsWith(' ')
      ? DocumentBlockAlignment.center
      : DocumentBlockAlignment.right;
  return (
    markup: sizedDivider == null ? markup : '$documentDivider${width!.clamp(10, 100)}$documentDivider',
    photoId: photo?.group(1),
    widthPercent: (width ?? defaultWidth).clamp(10, 100),
    alignment: alignment,
  );
}

String alignDocumentVisualBlock(
  String markup,
  DocumentBlockAlignment alignment,
) => switch (alignment) {
  DocumentBlockAlignment.left => markup,
  DocumentBlockAlignment.center => '| $markup |',
  DocumentBlockAlignment.right => '| $markup|',
};

String resizeDocumentVisualBlock(DocumentVisualBlock block, int width) {
  final id = block.photoId;
  final percent = width.clamp(10, 100);
  final markup = id == null
      ? '$documentDivider$percent$documentDivider'
      : (percent == 100
            ? '<photo id="$id">'
            : '<photo id="$id" width="$percent%">');
  return alignDocumentVisualBlock(markup, block.alignment);
}

final _documentTokens = RegExp(
  '${codeMarkup.pattern.replaceFirst(r'|$', r'|(?![\s\S])')}|'
  r'\[\[[^\r\n]*?\]\]|(?<comment><!--[\s\S]*?(?:-->|(?![\s\S])))',
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
    if ((token as RegExpMatch).namedGroup('comment') == null)
      return token.group(0)!;
    return token.group(0)!.replaceAll(RegExp(r'[^\r\n]'), ' ');
  });

  late final List<({int start, int end})> removals = _removals();

  List<({int start, int end})> _removals() {
    final result = <({int start, int end})>[];
    for (final range in ranges.map(_removal)) {
      if (result.isNotEmpty && result.last.end >= range.start) {
        final previous = result.removeLast();
        result.add((
          start: previous.start,
          end: range.end > previous.end ? range.end : previous.end,
        ));
      } else {
        result.add(range);
      }
    }
    return result;
  }

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
      if (range.start > start)
        buffer.write(source.substring(start, range.start));
      if (range.end > start) start = range.end;
    }
    buffer.write(source.substring(start));
    return buffer.toString();
  }
}

final documentListMarker = RegExp(r'^([ \t]*)(?:(\d{1,9})\.|(-|–))[ \t]+');

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

import '../capture/attachment_indicators.dart';
import 'element_store.dart';
import 'dart:math';
import 'tag_colors.dart';

import 'package:flutter/material.dart';

final _random = Random();
final _wordHues = <String, double>{};
void ensureWordColor(String word) {
  _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
}

void forgetWordColor(String word) => _wordHues.remove(word);

void renameWordColor(String oldText, String newText) {
  ensureWordColor(oldText);
  _wordHues[newText] = _wordHues.remove(oldText)!;
}

const starterWords = ['관찰', '질문', '연결', '기억', '성장'];

Color wordBackgroundColor(BuildContext context, String word, {bool? closed}) {
  if (closed ?? (elements.records[word]?.hiddenFromSearch == true)) return Theme.of(context).brightness == Brightness.dark ? const Color(0xFF303030) : const Color(0xFFBABABA);
  final custom = elements.records[word]?.labelColor;
  if (custom != null) return HSLColor.fromColor(Color(custom)).withLightness(Theme.of(context).brightness == Brightness.dark ? .25 : .9).toColor();
  final hue = _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
  return HSLColor.fromAHSL(
    1,
    hue,
    .55,
    Theme.of(context).brightness == Brightness.dark ? .25 : .9,
  ).toColor();
}

String badgeLabel(String word) => word.replaceAll(RegExp(r'[\r\n\u2028\u2029]+'), ' ');

Widget elementBadge(BuildContext context, String word) => Chip(
  label: Text(badgeLabel(word), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
    semanticsLabel: word, style: TextStyle(color: wordColor(context, word))),
  backgroundColor: wordBackgroundColor(context, word),
  shape: const StadiumBorder(),
  side: BorderSide.none,
  visualDensity: VisualDensity.compact,
);

Color wordColor(BuildContext context, String word) {
  if (elements.records[word]?.hiddenFromSearch == true) return Theme.of(context).brightness == Brightness.dark ? const Color(0xFF969696) : const Color(0xFF303030);
  final custom = elements.records[word]?.labelColor;
  if (custom != null) return HSLColor.fromColor(Color(custom)).withLightness(Theme.of(context).brightness == Brightness.dark ? .9 : .23).toColor();
  final hue = _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
  return HSLColor.fromAHSL(
    1,
    hue,
    .5,
    Theme.of(context).brightness == Brightness.dark ? .9 : .23,
  ).toColor();
}

TextRange? _badgeMatch(String text, String query) {
  if (query.trim().isEmpty) return null;
  final normalized = StringBuffer();
  final starts = <int>[], ends = <int>[];
  var offset = 0;
  for (final character in text.characters) {
    final folded = _hangulParts(character.toLowerCase());
    normalized.write(folded);
    for (var i = 0; i < folded.length; i++) {
      starts.add(offset);
      ends.add(offset + character.length);
    }
    offset += character.length;
  }
  final needle = _hangulParts(badgeLabel(query.trim()).toLowerCase());
  final at = normalized.toString().indexOf(needle);
  return at < 0 ? null : TextRange(start: starts[at], end: ends[at + needle.length - 1]);
}

InlineSpan _badgeExcerpt(BuildContext context, String word, String query, double width) {
  final text = badgeLabel(word);
  if (text.isEmpty) return const TextSpan(text: '');
  final match = _badgeMatch(text, query);
  // Let the text renderer ellipsize ordinary labels in a single layout pass.
  if (match == null) return TextSpan(text: text);
  final boundaries = <int>[0];
  for (final character in text.characters) { boundaries.add(boundaries.last + character.length); }
  InlineSpan span(int first, int last) {
    final start = boundaries[first], end = boundaries[last];
    final from = match.start.clamp(start, end);
    final to = match.end.clamp(from, end);
    return TextSpan(children: [
      if (start > 0) const TextSpan(text: '…'),
      TextSpan(text: text.substring(start, from)),
      if (to > from) TextSpan(text: text.substring(from, to),
        style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
      TextSpan(text: text.substring(to, end)),
      if (end < text.length) const TextSpan(text: '…'),
    ]);
  }
  final style = Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 12, fontWeight: FontWeight.w500);
  bool fits(int first, int last) {
    final painter = TextPainter(text: TextSpan(style: style, children: [span(first, last)]),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
    final fits = painter.width <= width;
    painter.dispose();
    return fits;
  }
  if (fits(0, boundaries.length - 1)) return span(0, boundaries.length - 1);
  var first = boundaries.indexOf(match.start);
  var last = boundaries.indexOf(match.end);
  while (last > first + 1 && !fits(first, last)) { last--; }
  while (true) {
    var expanded = false;
    if (first > 0 && fits(first - 1, last)) { first--; expanded = true; }
    if (last < boundaries.length - 1 && fits(first, last + 1)) { last++; expanded = true; }
    if (!expanded) break;
  }
  return span(first, last);
}

class WordBadge extends StatelessWidget {
  const WordBadge({
    super.key,
    required this.word,
    required this.onTap,
    this.displayText,
    this.selected = false,
    this.tag = false,
    this.compact = false,
    this.dense = false, this.project = false, this.memo = false, this.labelTarget = false,
    this.query = '',
    this.fullText = false, this.singleLine = false, this.square = false,
    this.onLongPress,
    this.onDoubleTap,
  });
  final String word;
  final String? displayText;
  final String query;
  final VoidCallback onTap;
  final bool selected;
  final bool tag;
  final bool compact;
  final bool dense, project, memo, labelTarget;
  final bool fullText, singleLine, square;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, constraints) {
    final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width - 24;
    final labelColor = tag ? Color(hashtagColors[word.replaceFirst('#', '')] ?? 0xFF90A4AE) : null;
    final record = tag ? null : elements.records[word];
    final indicators = record != null && AttachmentIndicators.hasAttachments(record);
    final title = singleLine ? (displayText ?? word).replaceAll(RegExp(r'[\r\n]+'), ' ') : displayText ?? word;
    var prefixWidth = 0.0;
    if (project || memo || labelTarget) {
      final prefix = TextPainter(text: TextSpan(text: project ? '문서:' : labelTarget ? '라벨:' : '메모:', style: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 12, fontWeight: FontWeight.w300)),
        textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
      prefixWidth = prefix.width;
      prefix.dispose();
    }
    final label = project || memo || labelTarget ? TextSpan(children: [
      TextSpan(text: project ? '문서:' : labelTarget ? '라벨:' : '메모:', style: const TextStyle(fontWeight: FontWeight.w300)),
      TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: [
        _badgeExcerpt(context, title, query, (maxWidth - 24 - prefixWidth).clamp(0.0, double.infinity)),
      ]),
    ]) : fullText ? TextSpan(text: title) : _badgeExcerpt(context, title, query, maxWidth - 24);
    final badge = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: TextButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      style: TextButton.styleFrom(
        backgroundColor: record?.hiddenFromSearch == true ? wordBackgroundColor(context, word) : labelColor?.withValues(alpha: dark ? .3 : .18) ?? wordBackgroundColor(context, word),
        foregroundColor: record?.hiddenFromSearch == true ? wordColor(context, word) : labelColor ?? wordColor(context, word),
        minimumSize: Size(0, dense ? 25 : 30),
        padding: EdgeInsets.symmetric(horizontal: dense ? 5 : compact ? 7 : 12, vertical: dense ? 1 : compact ? 3 : 5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: fullText ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: selected ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none) : StadiumBorder(
          side: selected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
        textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w500),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (indicators) ...[AttachmentIndicators(record: record), const SizedBox(width: 4)],
        Flexible(child: Text.rich(label,
        maxLines: square ? ((constraints.maxHeight - 20) / 20).floor().clamp(1, 100) : fullText && !singleLine ? null : 1, softWrap: fullText && !singleLine, overflow: square ? TextOverflow.ellipsis : fullText && !singleLine ? TextOverflow.visible : TextOverflow.ellipsis, semanticsLabel: project ? '문서:$title' : labelTarget ? '라벨:$title' : memo ? '메모:$title' : title)),
      ]),
    ));
    return onDoubleTap == null ? badge : GestureDetector(onDoubleTap: onDoubleTap, child: badge);
    });
  }
}

String wordPrefix(TextEditingValue value) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return '';
  return RegExp(r'[^\s.,!?;:،؛؟()\[\]{}]+$')
          .stringMatch(value.text.substring(0, value.selection.extentOffset)) ??
      '';
}

/// Active hashtag can start immediately after prose or another hashtag.
String tagPrefix(TextEditingValue value) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return '';
  final before = value.text.substring(0, value.selection.extentOffset);
  return RegExp(r'#[^\s#.,!?;:،؛؟()\[\]{}]*$').stringMatch(before) ?? '';
}

bool startsWord(String word, String query) =>
    _hangulParts(word.toLowerCase())
        .startsWith(_hangulParts(query.toLowerCase()));

bool matchesWord(String word, String query) {
  if (startsWord(word, query)) return true;
  return query.characters.length >= 2 &&
      _hangulParts(word.toLowerCase())
          .contains(_hangulParts(query.toLowerCase()));
}

List<String> wordSuggestions(List<String> words, String query) {
  final matches = words.where((word) => matchesWord(word, query)).toList();
  matches.sort((a, b) {
    final priority = (startsWord(a, query) ? 0 : 1).compareTo(
      startsWord(b, query) ? 0 : 1,
    );
    return priority != 0 ? priority : a.compareTo(b);
  });
  return matches;
}

Map<String, double> exportWordColors() => Map.of(_wordHues);
void restoreWordColors(Map<String, double> colors) {
  _wordHues
    ..clear()
    ..addAll(colors);
}

// Compare composing Hangul without changing the user's composing text.
String _hangulParts(String text) {
  const initial = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  const vowels = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  const finalLetters = ' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
  final result = StringBuffer();
  for (final rune in text.runes) {
    final index = rune - 0xAC00;
    if (index < 0 || index >= 11172) {
      result.writeCharCode(rune);
      continue;
    }
    result.write(initial[index ~/ 588]);
    result.write(vowels[(index % 588) ~/ 28]);
    if (index % 28 != 0) result.write(finalLetters[index % 28]);
  }
  return result.toString();
}

String completionPrefix(TextEditingValue value, List<String> words) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return '';
  final before = value.text.substring(0, value.selection.extentOffset);
  String? exact;
  for (final word in words) {
    if (word.isEmpty || !before.toLowerCase().endsWith(word.toLowerCase())) continue;
    if (exact == null || word.length > exact.length) exact = word;
  }
  if (exact != null) return before.substring(before.length - exact.length);
  final token = wordPrefix(value);
  if (words.any((word) => matchesWord(word, token))) return token;
  final characters = token.characters.toList();
  for (var i = 1; i < characters.length; i++) {
    final suffix = characters.skip(i).join();
    if (words.any((word) => matchesWord(word, suffix))) return suffix;
  }
  return token;
}

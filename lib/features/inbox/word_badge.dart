import 'dart:math';

import 'package:flutter/material.dart';

final _random = Random();
final _wordHues = <String, double>{};
void ensureWordColor(String word) {
  _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
}

void renameWordColor(String oldText, String newText) {
  ensureWordColor(oldText);
  _wordHues[newText] = _wordHues.remove(oldText)!;
}

const starterWords = ['관찰', '질문', '연결', '기억', '성장'];

Color wordBackgroundColor(BuildContext context, String word) {
  final hue = _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
  return HSLColor.fromAHSL(
    1,
    hue,
    .55,
    Theme.of(context).brightness == Brightness.dark ? .25 : .9,
  ).toColor();
}

Widget elementBadge(BuildContext context, String word) => Chip(
  label: Text(word, style: TextStyle(color: wordColor(context, word))),
  backgroundColor: wordBackgroundColor(context, word),
  shape: const StadiumBorder(),
  side: BorderSide.none,
  visualDensity: VisualDensity.compact,
);

Color wordColor(BuildContext context, String word) {
  final hue = _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
  return HSLColor.fromAHSL(
    1,
    hue,
    .5,
    Theme.of(context).brightness == Brightness.dark ? .9 : .23,
  ).toColor();
}

class WordBadge extends StatelessWidget {
  const WordBadge({
    super.key,
    required this.word,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });
  final String word;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    final hue = _wordHues.putIfAbsent(word, () => _random.nextDouble() * 360);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      style: TextButton.styleFrom(
        backgroundColor: HSLColor.fromAHSL(
          1,
          hue,
          .55,
          dark ? .25 : .9,
        ).toColor(),
        foregroundColor: HSLColor.fromAHSL(
          1,
          hue,
          .5,
          dark ? .9 : .23,
        ).toColor(),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: StadiumBorder(
          side: selected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(word),
    );
  }
}

String wordPrefix(TextEditingValue value) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return '';
  return RegExp(r'[^\s.,!?;:،؛؟()\[\]{}]+$')
          .stringMatch(value.text.substring(0, value.selection.extentOffset)) ??
      '';
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

String completionPrefix(TextEditingValue value, List<String> words) =>
    wordPrefix(value);

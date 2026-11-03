import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';

void main() {
  const phrase = '앞부분의 긴 문장이 여러 번 이어지고 다른 설명이 이어집니다 검색어가 나오는 중간 위치 그리고 뒷부분의 긴 문장이 한참 더 이어집니다';
  testWidgets('query stays visible between leading and trailing ellipses', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WordBadge(word: phrase, query: '중간 위치', onTap: () {}))));
    final text = tester.widget<Text>(find.descendant(of: find.byType(WordBadge), matching: find.byType(Text)));
    final label = text.textSpan!.toPlainText();
    expect(label, startsWith('…'));
    expect(label, endsWith('…'));
    expect(label, contains('중간 위치'));
    final span = text.textSpan as TextSpan;
    expect(span.children!.whereType<TextSpan>().any((s) => s.text == '중간 위치' && s.style?.fontWeight == FontWeight.w700), isTrue);
    expect(tester.widget<WordBadge>(find.byType(WordBadge)).word, phrase);
  });

  testWidgets('assist excerpts do not alter the inserted original sentence', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [phrase])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '중간');
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('suggestion-$phrase'));
    final label = tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text))).textSpan!.toPlainText();
    expect(label, contains('중간'));
    expect(label, startsWith('…'));
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, phrase);
  });

  testWidgets('partial Hangul syllable focuses the complete matching characters', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WordBadge(
      word: '생각을 적는 긴 글귀입니다', query: '생가', onTap: () {}))));
    final span = tester.widget<Text>(find.descendant(of: find.byType(WordBadge), matching: find.byType(Text))).textSpan as TextSpan;
    expect(span.children!.whereType<TextSpan>().any((s) => s.text == '생각' && s.style?.fontWeight == FontWeight.w700), isTrue);
  });
}

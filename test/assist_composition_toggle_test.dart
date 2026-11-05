import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('first shortcut enters an automatically highlighted exact match and re-enters after edits', (tester) async {
    final c = TextEditingController(); final f = FocusNode();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(controller: c,
      focus: f, words: const ['생각', '기억'], onWord: (_) {}, child: TextField(controller: c, focusNode: f)))));
    Future<void> toggle() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }
    bool selected(String word) => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == word && b.selected);
    for (final word in ['생각', '기억']) {
      await tester.enterText(find.byType(TextField), word); await tester.pumpAndSettle();
      expect(selected(word), isTrue);
      await toggle(); expect(selected(word), isTrue);
      await toggle(); expect(selected(word), isFalse);
      await toggle(); expect(selected(word), isTrue);
    }
    await tester.pumpWidget(const SizedBox()); c.dispose(); f.dispose();
  });
  for (final tag in [false, true]) {
    testWidgets('multi-character composition cannot undo selection toggle (tag=$tag)', (tester) async {
      final c = TextEditingController(); final f = FocusNode();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(controller: c,
        focus: f, words: const ['생각 정리'], tags: const ['생각정리'], onWord: (_) {}, onTag: (_) {},
        child: TextField(controller: c, focusNode: f)))));
      await tester.tap(find.byType(TextField));
      final text = tag ? '#생각' : '생각';
      final composing = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: tag ? 1 : 0, end: text.length));
      tester.testTextInput.updateEditingValue(composing); await tester.pumpAndSettle();
      Future<void> toggle() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }
      bool selected() => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.selected);
      final releases = tester.testTextInput.log.where((call) => call.method == 'TextInput.clearClient').length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.log.where((call) => call.method == 'TextInput.clearClient').length, greaterThan(releases));
      expect(c.value.composing, TextRange.empty);
      expect(c.text, text);
      expect(f.hasFocus, isTrue);
      expect(selected(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selected(), isTrue);
      tester.testTextInput.updateEditingValue(composing); await tester.pumpAndSettle();
      await toggle(); expect(selected(), isFalse);
      tester.testTextInput.updateEditingValue(composing); await tester.pumpAndSettle();
      expect(selected(), isFalse);
      expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
      await toggle(); expect(selected(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
      expect(selected(), isFalse);
      expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); c.dispose(); f.dispose();
    });
  }
}

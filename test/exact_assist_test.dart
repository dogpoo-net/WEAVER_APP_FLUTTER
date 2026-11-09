import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_binding.dart';

Future<void> toggleAssist(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  testWidgets('exact phrase selects automatically, escape stays dismissed, and enter binds', (tester) async {
    elements.clear(); elements.add('작은 생각');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: const ParagraphEditor(words: ['작은 생각', '작은 생각들'])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '오늘 작은 생각'); await tester.pumpAndSettle();
    bool selected() => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == '작은 생각' && b.selected);
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
    expect(selected(), isFalse);
    await toggleAssist(tester); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '오늘 작은 생각');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Ctrl Space selects a composing exact Hangul match once and exits with Escape after IME echo', (tester) async {
    elements.clear(); elements.add('생각');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: const ParagraphEditor(words: ['생각', '생각 정리'])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.tap(field); await tester.pumpAndSettle();
    const composing = TextEditingValue(text: '생각', selection: TextSelection.collapsed(offset: 2), composing: TextRange(start: 0, end: 2));
    bool selected() => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == '생각' && b.selected);
    tester.testTextInput.updateEditingValue(composing);
    await toggleAssist(tester); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    tester.testTextInput.updateEditingValue(composing); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
    expect(selected(), isFalse);
    tester.testTextInput.updateEditingValue(composing.copyWith(composing: TextRange.empty));
    await tester.pumpAndSettle();
    expect(selected(), isFalse);
    await toggleAssist(tester); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('quick memo completes existing phrases without saving on assist enter', (tester) async {
    await tester.pumpWidget(const MyApp(requireLogin: false, ));
    elements.add('작은 생각');
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '오늘 작은'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-작은 생각'))); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '오늘 ');
    await tester.enterText(field, '작은 생각'); await tester.pumpAndSettle();
    expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == '작은 생각' && b.selected), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    final controller = tester.widget<TextField>(field).controller! as BoundTextController;
    expect(controller.bindings, isEmpty);
    await tester.enterText(field, '새 본문'); await tester.pumpAndSettle();
    expect(controller.text, '새 본문');
    expect(tester.takeException(), isNull);
  });
}

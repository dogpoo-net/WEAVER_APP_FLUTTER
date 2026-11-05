import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/word_badge.dart';

Future<void> shortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}
void main() {
  testWidgets('hash opens tags and Control Space adds a tag without saving memo text', (tester) async {
    await tester.pumpWidget(const MyApp());
    elements.add('원소 #독서 #기억');
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '#'); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-#독서')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggestion-원소')), findsNothing);
    await tester.enterText(field, '메모 #독'); await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft); await tester.pumpAndSettle();
    expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.selected), isFalse);
    await shortcut(tester); await tester.pumpAndSettle();
    expect(tester.widget<WordBadge>(find.byKey(const ValueKey('suggestion-#독서'))).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '메모 ');
    expect(find.byTooltip('#독서 태그 삭제'), findsOneWidget);
    expect(elements.words, ['원소']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('paragraph tag suggestions include saved paragraph-only tags and work by tap', (tester) async {
    elements.clear();
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [], availableTags: ['자료', '독서'])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '본문 #자'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-#자료'))); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '본문 ');
    expect(find.byTooltip('#자료 태그 삭제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Control alone leaves Hangul composing and Control Space opens empty memo assist', (tester) async {
    await tester.pumpWidget(const MyApp());
    elements.add('관찰');
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '관'); await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: '관', selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.value.composing.isCollapsed, isFalse);
    await tester.enterText(field, ''); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assist-popup')), findsNothing);
    await shortcut(tester); await tester.pumpAndSettle();
    expect(tester.widget<WordBadge>(find.byKey(const ValueKey('suggestion-관찰'))).selected, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

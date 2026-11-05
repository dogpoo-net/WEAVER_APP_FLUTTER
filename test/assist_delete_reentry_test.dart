import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/word_badge.dart';

Future<void> enterAssist(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}
void main() {
  for (final tags in [false, true]) {
    for (final pumpAfterDelete in [false, true]) {
      testWidgets('shortcut enters after deleting into an exact match (tags=$tags, frame=$pumpAfterDelete)', (tester) async {
        final controller = TextEditingController(); final focus = FocusNode();
        addTearDown(controller.dispose); addTearDown(focus.dispose);
        final prefix = tags ? '#' : '';
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(
          controller: controller, focus: focus, words: const ['관찰', '관찰하기'], tags: const ['관찰', '관찰하기'],
          onWord: (_) {}, onTag: tags ? (_) {} : null,
          child: TextField(controller: controller, focusNode: focus)))));
        await tester.enterText(find.byType(TextField), '$prefix관찰하'); await tester.pumpAndSettle();
        tester.testTextInput.updateEditingValue(TextEditingValue(text: '$prefix관찰', selection: TextSelection.collapsed(offset: prefix.length + 2)));
        if (pumpAfterDelete) await tester.pumpAndSettle();
        // With a settled frame, an exact match is already selected.
        if (pumpAfterDelete) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
        }
        await enterAssist(tester); await tester.pumpAndSettle();
        bool selected() => tester.widget<WordBadge>(find.byKey(ValueKey('suggestion-$prefix관찰'))).selected;
        expect(selected(), isTrue);
        // The second shortcut leaves selection while keeping the popup open.
        await enterAssist(tester); await tester.pumpAndSettle();
        expect(selected(), isFalse);
        await enterAssist(tester); await tester.pumpAndSettle();
        expect(selected(), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
        expect(selected(), isFalse);
        await enterAssist(tester); await tester.pumpAndSettle();
        expect(selected(), isTrue);
        expect(controller.text, '$prefix관찰');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

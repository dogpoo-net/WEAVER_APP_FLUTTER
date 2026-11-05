import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  for (final tag in [false, true]) {
    testWidgets('Escape exits selection then dismisses assist (tag=$tag)', (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(
        controller: controller, focus: focus, words: const ['독서'], tags: const ['독서'],
        onWord: (_) {}, onTag: (_) {}, child: TextField(controller: controller, focusNode: focus)))));
      await tester.enterText(find.byType(TextField), tag ? '문장#' : '독');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).single.selected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
      expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).single.selected, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-popup')), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(controller.text, tag ? '문장#' : '독');
      await tester.pumpWidget(const SizedBox()); controller.dispose(); focus.dispose();
    });
  }
}

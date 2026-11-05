import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  for (final tag in [false, true]) {
    for (final key in [PhysicalKeyboardKey.enter, PhysicalKeyboardKey.numpadEnter]) {
      testWidgets('IME Process Enter accepts selected candidate (tag=$tag, key=$key)', (tester) async {
        final controller = TextEditingController(); final focus = FocusNode();
        addTearDown(controller.dispose); addTearDown(focus.dispose);
        String? chosen;
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(
          controller: controller, focus: focus, words: const ['독서'], tags: const ['독서'],
          onWord: (word) => chosen = word, onTag: tag ? (value) => chosen = '#$value' : null,
          child: TextField(controller: controller, focusNode: focus)))));
        await tester.enterText(find.byType(TextField), tag ? '#독' : '독'); await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).single.selected, isTrue);
        final handler = tester.widgetList<Focus>(find.descendant(of: find.byType(CaretAssist), matching: find.byType(Focus)))
          .firstWhere((widget) => !widget.canRequestFocus && widget.onKeyEvent != null).onKeyEvent!;
        final result = handler(focus, KeyDownEvent(logicalKey: LogicalKeyboardKey.process, physicalKey: key, timeStamp: Duration.zero));
        await tester.pumpAndSettle();
        expect(result, KeyEventResult.handled);
        expect(chosen, tag ? '#독서' : '독서');
        expect(controller.text, tag ? '#독' : '독');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

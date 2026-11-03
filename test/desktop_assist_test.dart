import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/caret_assist.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('single candidate toggles once before overlay refresh and survives IME callbacks', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(
      words: ['생각', '독서'], initial: [Paragraph('없는 후보', ParagraphRole.body)])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assist-popup')), findsNothing);
    final controller = tester.widget<TextField>(field).controller!;
    bool selected(String word) => tester.widgetList<WordBadge>(find.byType(WordBadge))
        .any((badge) => badge.word == word && badge.selected);
    for (final entry in {'생': '생각', '독': '독서'}.entries) {
      // No pump between input and Ctrl: the candidate overlay still has old data.
      tester.testTextInput.updateEditingValue(TextEditingValue(text: entry.key,
        selection: const TextSelection.collapsed(offset: 1), composing: const TextRange(start: 0, end: 1)));
      await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selected(entry.value), isTrue);
      // Browsers may report composing again after Ctrl has already committed it.
      tester.testTextInput.updateEditingValue(TextEditingValue(text: entry.key,
        selection: const TextSelection.collapsed(offset: 1), composing: const TextRange(start: 0, end: 1)));
      await tester.pumpAndSettle();
      expect(selected(entry.value), isTrue);
      expect(controller.selection.extentOffset, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, entry.value);
      expect(controller.text, isNot(contains('\n')));
    }
    // Returning to previously inserted text must not keep an old dismissal alive.
    controller.value = const TextEditingValue(text: '독서 다른 글', selection: TextSelection.collapsed(offset: 7));
    controller.value = const TextEditingValue(text: '독서', selection: TextSelection.collapsed(offset: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-독서')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selected('독서'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selected('독서'), isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));

  testWidgets(
    'one Control toggles during Korean composition without moving caret',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: ParagraphEditor(words: ['생각', '생각 정리'])),
      );
      final field = find.byKey(const ValueKey('paragraph-0'));
      await tester.tap(field);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '생',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(field).controller!;
      final handler = tester
          .widgetList<Focus>(
            find.descendant(
              of: find.byType(CaretAssist),
              matching: find.byType(Focus),
            ),
          )
          .firstWhere((f) => !f.canRequestFocus && f.onKeyEvent != null);
      final node = FocusNode();
      addTearDown(node.dispose);
      handler.onKeyEvent!(
        node,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.process,
          timeStamp: Duration.zero,
        ),
      );
      handler.onKeyEvent!(
        node,
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.process,
          timeStamp: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.text, '생');
      expect(controller.selection.extentOffset, 1);
      expect(controller.value.composing.isCollapsed, isTrue);
      expect(
        tester
            .widgetList<WordBadge>(find.byType(WordBadge))
            .where((w) => w.selected)
            .single
            .word,
        '생각',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<WordBadge>(find.byType(WordBadge))
            .any((w) => w.selected),
        isFalse,
      );
      // A Ctrl shortcut must not toggle or force composition to end.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '생',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<WordBadge>(find.byType(WordBadge))
            .any((w) => w.selected),
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, '생각 정리');
    },
  );

  test('one character prefixes, two contain, prefixes rank first', () {
    expect(wordSuggestions(['생각', '작은 생각', '생각 정리'], '생'), ['생각', '생각 정리']);
    expect(wordSuggestions(['작은 생각', '생각 정리', '생각'], '생각'), [
      '생각',
      '생각 정리',
      '작은 생각',
    ]);
    expect(
      completionPrefix(
        const TextEditingValue(
          text: '문장\n생',
          selection: TextSelection.collapsed(offset: 4),
        ),
        [],
      ),
      '생',
    );
  });
  testWidgets('control toggles badge navigation with spatial arrows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final words = List.generate(24, (i) => '원소${i.toString().padLeft(2, '0')}');
    await tester.pumpWidget(MaterialApp(home: ParagraphEditor(words: words)));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '원');
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field).controller!;
    String selected() => tester
        .widgetList<WordBadge>(find.byType(WordBadge))
        .singleWhere((b) => b.selected)
        .word;
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selected(), words.first);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected(), words[1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selected(), words.first);
    final origin = tester.getCenter(
      find.byKey(ValueKey('suggestion-${words.first}')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final below = selected();
    expect(words.indexOf(below), greaterThan(1));
    expect(
      tester.getCenter(find.byKey(ValueKey('suggestion-$below'))).dy,
      greaterThan(origin.dy),
    );
    expect(controller.selection.extentOffset, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(selected(), words.first);
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 0);
    expect(
      tester
          .widgetList<WordBadge>(find.byType(WordBadge))
          .any((b) => b.selected),
      isFalse,
    );
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, words.first);
  });
}

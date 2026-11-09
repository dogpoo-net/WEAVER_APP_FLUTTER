import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('platform newline and delayed key echo never leave a blank line', (tester) async {
    await tester.pumpWidget(const MyApp(requireLogin: false, ));
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '플랫폼 입력');
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: '플랫폼 입력\n', selection: TextSelection.collapsed(offset: 7)));
    await tester.pumpAndSettle();
    expect(elements.words, ['플랫폼 입력']);
    expect(tester.widget<TextField>(field).controller!.text, '');
    await tester.enterText(field, '키보드 입력');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: '키보드 입력\n', selection: TextSelection.collapsed(offset: 7)));
    await tester.pumpAndSettle();
    expect(elements.words, ['플랫폼 입력', '키보드 입력']);
    expect(tester.widget<TextField>(field).controller!.text, '');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));

  testWidgets(
    'one enter commits Korean composition and saves once',
    (tester) async {
      await tester.pumpWidget(const MyApp(requireLogin: false, ));
      final field = find.byKey(const ValueKey('quick-memo'));
      await tester.tap(field);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '기억',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      expect(elements.words, ['기억']);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '기억',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(elements.words, ['기억']);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      // A platform that leaves composing set until key-up also saves once.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '생각',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(elements.words, ['기억', '생각']);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  for (final modifier in [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.altLeft]) {
    for (final nativeNewline in [false, true]) {
      testWidgets('Korean IME modifier Enter inserts exactly one newline ($modifier, native=$nativeNewline)', (tester) async {
        await tester.pumpWidget(const MyApp(requireLogin: false, ));
        final field = find.byKey(const ValueKey('quick-memo'));
        await tester.tap(field);
        tester.testTextInput.updateEditingValue(const TextEditingValue(text: '가',
          selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
        await tester.pump();
        await tester.sendKeyDownEvent(modifier);
        final handler = tester.widget<Focus>(find.byKey(const ValueKey('quick-memo-keyboard'))).onKeyEvent!;
        final focus = tester.widget<TextField>(field).focusNode!;
        handler(focus, const KeyDownEvent(logicalKey: LogicalKeyboardKey.process,
          physicalKey: PhysicalKeyboardKey.enter, timeStamp: Duration.zero));
        final committed = nativeNewline ? '각\n' : '각';
        tester.testTextInput.updateEditingValue(TextEditingValue(text: committed,
          selection: TextSelection.collapsed(offset: committed.length)));
        handler(focus, const KeyUpEvent(logicalKey: LogicalKeyboardKey.process,
          physicalKey: PhysicalKeyboardKey.enter, timeStamp: Duration.zero));
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        expect(controller.text, '각\n');
        expect(controller.selection.extentOffset, 2);
        expect(elements.words, isEmpty);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(controller.text, '각\n');
        expect(elements.words, isEmpty);
        if (!nativeNewline) {
          // A late IME commit must not erase the manually inserted newline.
          tester.testTextInput.updateEditingValue(const TextEditingValue(text: '각',
            selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
          await tester.pumpAndSettle();
          expect(controller.text, '각\n');
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(controller.text, '각');
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
    }
    testWidgets('Korean IME still composing on modifier Enter key-up inserts newline ($modifier)', (tester) async {
      await tester.pumpWidget(const MyApp(requireLogin: false, ));
      final field = find.byKey(const ValueKey('quick-memo'));
      await tester.tap(field);
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '한글',
        selection: TextSelection.collapsed(offset: 2), composing: TextRange(start: 1, end: 2)));
      await tester.pump();
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '한글\n');
      expect(elements.words, isEmpty);
    }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
  }

  testWidgets(
    'desktop enter saves; shift and alt enter insert newline',
    (tester) async {
      await tester.pumpWidget(const MyApp(requireLogin: false, ));
      final field = find.byKey(const ValueKey('quick-memo'));
      await tester.enterText(field, '첫째');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.widget<TextField>(field).controller!.text, '첫째\n');
      await tester.enterText(field, '첫째\n둘째');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(tester.widget<TextField>(field).controller!.text, '첫째\n둘째\n');
      expect(elements.words, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(elements.words, ['첫째\n둘째']);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}

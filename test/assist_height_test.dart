import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';

void main() {
  for (final count in [1, 2, 4]) {
    testWidgets('$count badge rows shrink to content with a three-row maximum', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final words = List.generate(count, (i) => '가나다라마바사아자차카타파하생각$i');
      await tester.pumpWidget(MaterialApp(home: ParagraphEditor(words: words)));
      await tester.tap(find.byKey(const ValueKey('paragraph-0')));
      await tester.pumpAndSettle();
      final popup = find.byKey(const ValueKey('assist-popup'));
      final badgeHeight = tester.getSize(find.byKey(ValueKey('suggestion-${words.first}'))).height;
      final rows = count.clamp(1, 3);
      expect(tester.getSize(popup).height, closeTo(badgeHeight * rows + 6 * (rows - 1) + 16, 1));
      if (count > 3) {
        final scroll = find.descendant(of: popup, matching: find.byType(Scrollable));
        final bounds = tester.getRect(popup);
        await tester.scrollUntilVisible(find.byKey(ValueKey('suggestion-${words.last}')), 50, scrollable: scroll);
        await tester.pumpAndSettle();
        expect(tester.getRect(popup), bounds);
        await tester.tap(find.byKey(ValueKey('suggestion-${words.last}')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0'))).controller!.text, words.last);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

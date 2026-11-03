import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('badge is single line but insertion keeps the original line breaks', (tester) async {
    const phrase = '첫 번째 줄\n두 번째 줄';
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [phrase])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('suggestion-$phrase'));
    final label = tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text)));
    expect(label.textSpan!.toPlainText(), '첫 번째 줄 두 번째 줄');
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, phrase);
  });

  testWidgets('metadata chip also displays a single line', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: elementBadgeTest())));
    final text = tester.widget<Text>(find.text('첫 줄 다음 줄'));
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
  });
}

Widget elementBadgeTest() => Builder(builder: (context) => elementBadge(context, '첫 줄\r\n다음 줄'));

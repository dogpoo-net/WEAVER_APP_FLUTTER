import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';

void main() {
  const word = '첫 줄\n둘째 줄';
  testWidgets('multiline assist leaves the caret on the next line', (tester) async {
    elements.clear(); elements.add(word);
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [word])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '첫'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-$word'))); await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, '$word\n');
    expect(controller.selection.extentOffset, word.length + 1);
    await tester.enterText(field, '$word\n추가 글'); await tester.pumpAndSettle();
    expect(controller.text, '$word\n추가 글');
    expect(tester.takeException(), isNull);
  });

}

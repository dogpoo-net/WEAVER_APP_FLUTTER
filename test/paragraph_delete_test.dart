import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';

void main() {
  testWidgets('delete confirmation preserves other paragraphs and shifted focus', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [], initial: [
      Paragraph('첫 문단', ParagraphRole.title),
      Paragraph('삭제 대상', ParagraphRole.body),
      Paragraph('마지막 문단', ParagraphRole.subtitle),
    ])));
    await tester.tap(find.byKey(const ValueKey('delete-paragraph-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('delete-paragraph-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    final first = tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0')));
    final last = tester.widget<TextField>(find.byKey(const ValueKey('paragraph-1')));
    expect(first.controller!.text, '첫 문단');
    expect(last.controller!.text, '마지막 문단');
    expect(tester.widgetList<ToggleButtons>(find.byType(ToggleButtons)).last.isSelected,
      [false, true, false]);
    await tester.tap(find.byKey(const ValueKey('paragraph-1')));
    await tester.pumpAndSettle();
    expect(last.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byKey(const ValueKey('paragraph-1')), '수정한 마지막 문단');
    await tester.pumpAndSettle();
    expect(first.controller!.text, '첫 문단');
    expect(last.controller!.text, '수정한 마지막 문단');
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the final blank paragraph keeps one usable input', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: [])));
    await tester.tap(find.byKey(const ValueKey('delete-paragraph-0')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '새 문단');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0'))).controller!.text, '새 문단');
    expect(tester.takeException(), isNull);
  });
}

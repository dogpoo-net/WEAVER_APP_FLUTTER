import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/document_markup.dart';

void main() {
  testWidgets('document contents are visible and jump to the heading', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final body = List.generate(100, (index) => '본문 $index').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: DocumentMarkup(
              text: '======문서======\n=====처음=====\n$body\n=====마지막=====\n$body',
            ),
          ),
        ),
      ),
    );
    expect(find.text('목차'), findsOneWidget);
    final tocEntry = find.widgetWithText(TextButton, '2. 마지막');
    expect(tocEntry.hitTestable(), findsOneWidget);
    await tester.tap(tocEntry);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(500));
    final heading = find.text('2. 마지막', findRichText: true).last;
    expect(tester.getTopLeft(heading).dy, closeTo(0, 1));
  });
}

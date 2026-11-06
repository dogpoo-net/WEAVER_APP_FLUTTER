import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('linked thoughts rebind one modal, retain drafts and save only the displayed thought', (tester) async {
    elements.clear();
    final a = elements.add('첫 생각 #첫태그'); final b = elements.add('다음 생각 #다음태그');
    elements.connect(a.id, [b.id]);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showElementMetadata(context, a.text), child: const Text('정보'))))));
    await tester.tap(find.text('정보')); await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('element-editor'));
    await tester.enterText(editor, '첫 생각 초안'); await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is WordBadge && w.word == b.text)); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, '다음 생각');
    expect(find.text('#다음태그'), findsOneWidget); expect(find.text('#첫태그'), findsNothing);
    await tester.tap(find.byWidgetPredicate((w) => w is WordBadge && w.word == a.text)); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).controller!.text, '첫 생각 초안');
    expect(a.text, '첫 생각');
    await tester.tap(find.byWidgetPredicate((w) => w is WordBadge && w.word == b.text)); await tester.pumpAndSettle();
    await tester.enterText(editor, '다음 생각 수정'); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장')); await tester.pumpAndSettle();
    expect(b.text, '다음 생각 수정'); expect(a.text, '첫 생각');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('정보'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

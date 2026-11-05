import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('metadata treats tags as separate editable data and keeps prose clean', (tester) async {
    elements.clear();
    final record = elements.add('원래 본문 #기존');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showElementMetadata(context, record.text), child: const Text('보기'))))));
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('element-editor'));
    expect(tester.widget<TextField>(editor).controller!.text, '원래 본문');
    expect(find.descendant(of: find.byKey(const ValueKey('element-tags')), matching: find.text('#기존')), findsOneWidget);
    await tester.enterText(editor, '새 본문 #추가 '); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).controller!.text, '새 본문 ');
    expect(find.text('#추가'), findsOneWidget);
    expect(record.tags, {'기존'});
    await tester.tap(find.byTooltip('#기존 태그 삭제')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장')); await tester.pumpAndSettle();
    expect(record.text, '새 본문');
    expect(record.tags, {'추가'});
    expect(record.text, isNot(contains('#')));
    expect(tester.takeException(), isNull);
  });
}

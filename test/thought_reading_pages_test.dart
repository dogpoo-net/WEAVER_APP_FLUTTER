import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('read, edit, append and reopen a labeled page', (tester) async {
    elements.clear();
    addTearDown(elements.clear);
    final thought = ElementRecord('첫 장');
    elements.records[thought.text] = thought;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showElementMetadata(context, thought.text),
        child: const Text('열기'),
      ),
    ))));
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    await tap(find.text('열기'));
    expect(find.text('1 / 1'), findsOneWidget);
    await tap(find.byTooltip('수정'));
    await tap(find.byTooltip('다음 페이지'));
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('element-editor')), '둘째 장');
    await tester.enterText(find.byKey(const ValueKey('thought-label-editor')), '두 번째 라벨');
    await tap(find.widgetWithText(FilledButton, '저장'));
    await tap(find.text('열기'));
    await tap(find.byTooltip('다음 페이지'));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('두 번째 라벨'), findsOneWidget);
  });
}

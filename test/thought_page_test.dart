import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  testWidgets('page connects thoughts bidirectionally and creates a thought', (tester) async {
    elements.clear(); final a = elements.add('생각 A'); final b = elements.add('생각 B');
    var changes = 0;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () => changes++)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('연결 모드')); await tester.pump();
    await tester.tap(find.text('생각 A')); await tester.pump();
    await tester.tap(find.text('생각 B')); await tester.pumpAndSettle();
    expect(a.connections, {b.id}); expect(b.connections, {a.id});
    await tester.tap(find.byTooltip('생각 만들기')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '새 생각');
    await tester.tap(find.text('만들기')); await tester.pumpAndSettle();
    expect(elements.records.containsKey('새 생각'), isTrue);
    expect(changes, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

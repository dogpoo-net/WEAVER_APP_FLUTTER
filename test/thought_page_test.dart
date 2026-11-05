import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';

void main() {
  testWidgets('page connects thoughts bidirectionally and creates a thought', (tester) async {
    elements.clear(); final a = elements.add('생각 A #안쪽'); final b = elements.add('생각 B');
    elements.add('상자 밖 생각 #바깥');
    final box = MemoBox('테스트 상자', ids: [a.id, b.id]);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(box: box, onChanged: () => changes++)));
    await tester.pumpAndSettle();
    expect(find.text('상자 밖 생각'), findsNothing);
    expect(find.text('#바깥'), findsNothing);
    expect(find.text('#안쪽'), findsWidgets);
    await tester.tap(find.byTooltip('연결 모드')); await tester.pump();
    await tester.tap(find.text('생각 A')); await tester.pump();
    await tester.tap(find.text('생각 B')); await tester.pumpAndSettle();
    expect(a.connections, {b.id}); expect(b.connections, {a.id});
    await tester.tap(find.byTooltip('생각 만들기')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '새 생각');
    await tester.tap(find.text('만들기')); await tester.pumpAndSettle();
    expect(elements.records.containsKey('새 생각'), isTrue);
    expect(box.elementIds, contains(elements.records['새 생각']!.id));
    expect(changes, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

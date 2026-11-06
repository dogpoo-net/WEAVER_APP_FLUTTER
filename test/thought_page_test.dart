import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';

void main() {
  setUp(() { pageGraphLayout = GraphLayout(); memoBoxes.clear(); });
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
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '새 생각');
    await tester.tap(find.text('만들기')); await tester.pumpAndSettle();
    expect(elements.records.containsKey('새 생각'), isTrue);
    expect(box.elementIds, contains(elements.records['새 생각']!.id));
    expect(changes, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('saved manual layouts have no destructive rearrange action', (tester) async {
    elements.clear();
    final a = elements.add('수동 배치 #태그');
    pageGraphLayout.positions[a.id] = const Offset(700, 200);
    pageGraphLayout.tags['tag:태그'] = const Offset(700, 500);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
    await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('기본 배치로 정리'), findsNothing);
    expect(find.byIcon(Icons.grid_on_outlined), findsNothing);
    expect(pageGraphLayout.positions[a.id], const Offset(700, 200));
    expect(pageGraphLayout.tags['tag:태그'], const Offset(700, 500));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dragging a thought into an empty box adds membership', (tester) async {
    elements.clear();
    final a = elements.add('담을 생각 #라벨');
    final box = MemoBox('빈 상자'); memoBoxes.add(box);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () => changes++)));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.text('담을 생각'));
    final target = tester.getCenter(find.byType(MemoBoxRegion));
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(from + const Offset(0, -80));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(box.elementIds, contains(a.id));
    expect(changes, greaterThan(0));
    expect(find.byWidgetPredicate((w) => w is Chip && w.side?.width == 2.5), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final inBox in [false, true]) {
    testWidgets('graph search, unlinked review and tag dragging (box=$inBox)', (tester) async {
      elements.clear();
      final a = elements.add('연결된 생각 #독서');
      final b = elements.add('참고 생각');
      final c = elements.add('홀로 생각 #검토');
      elements.connect(a.id, [b.id]);
      final box = MemoBox('검토 상자', ids: [a.id, b.id, c.id]);
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(box: inBox ? box : null, onChanged: () {})));
      await tester.pumpAndSettle();
      final tag = find.byKey(const ValueKey('graph-tag-독서'));
      final before = tester.getCenter(tag);
      await tester.drag(tag, const Offset(70, 35));
      await tester.pumpAndSettle();
      expect((tester.getCenter(tag) - before).distance, greaterThan(20));
      await tester.enterText(find.byKey(const ValueKey('graph-search')), '#검토');
      await tester.pumpAndSettle();
      expect(find.text('홀로 생각'), findsOneWidget);
      expect(find.text('연결된 생각'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('graph-search')), '');
      await tester.tap(find.text('연결 없음'));
      await tester.pumpAndSettle();
      expect(find.text('홀로 생각'), findsOneWidget);
      expect(find.text('연결된 생각'), findsNothing);
      expect(find.text('참고 생각'), findsNothing);
      expect(a.connections, contains(b.id));
      expect(elements.records.length, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

}

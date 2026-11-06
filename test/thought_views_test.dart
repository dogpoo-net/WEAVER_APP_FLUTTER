import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/puzzle_border.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout(); });
  for (final scoped in [false, true]) {
    testWidgets('three views share data and preserve box scope (scoped=$scoped)', (tester) async {
      final a = elements.add('안쪽 생각 #안쪽');
      final b = elements.add('연결된 생각');
      elements.add('바깥 생각 #바깥');
      elements.connect(a.id, [b.id]);
      final box = MemoBox('검토함', ids: [a.id, b.id]); memoBoxes.add(box);
      await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], initialBox: scoped ? box : null)));
      await tester.pumpAndSettle();
      expect(find.byType(ThoughtPage), findsOneWidget);
      expect(find.text('안쪽 생각'), findsOneWidget);
      expect(find.text('바깥 생각'), scoped ? findsNothing : findsOneWidget);
      final diagram = Map.of((scoped ? box.layout : pageGraphLayout).positions);
      await tester.tap(find.text('상자')); await tester.pumpAndSettle();
      expect(find.byType(ThoughtBoxView), findsOneWidget);
      expect(find.byKey(ValueKey('thought-${a.id}')), findsOneWidget);
      expect(find.text('바깥 생각'), scoped ? findsNothing : findsOneWidget);
      await tester.tap(find.text('페이지')); await tester.pumpAndSettle();
      expect(tester.widget<ThoughtPage>(find.byType(ThoughtPage)).blocks, isTrue);
      expect(find.byWidgetPredicate((w) => w is Card && w.shape is PuzzleBorder), findsWidgets);
      expect(find.text('#안쪽'), findsOneWidget);
      expect(tester.widget<MemoBoxRegion>(find.byType(MemoBoxRegion)).rectangular, isTrue);
      expect(find.text('바깥 생각'), scoped ? findsNothing : findsOneWidget);
      final layout = scoped ? box.layout : pageGraphLayout;
      expect(layout.blockLayout.positions.keys, containsAll([a.id, b.id]));
      expect(GraphLayout.fromJson(layout.toJson()).blockLayout.positions, layout.blockLayout.positions);
      await tester.tap(find.text('다이어그램')); await tester.pumpAndSettle();
      expect(tester.widget<ThoughtPage>(find.byType(ThoughtPage)).blocks, isFalse);
      expect(layout.positions, diagram);
      expect(a.connections, {b.id}); expect(b.connections, {a.id});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

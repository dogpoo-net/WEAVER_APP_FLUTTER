import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout(); });
  for (final blocks in [false, true]) {
    testWidgets('empty canvas pans at minimum zoom without moving contents ($blocks)', (tester) async {
      final record = elements.add('위치 유지');
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: blocks, onChanged: () {})));
      await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      final before = layout.positions[record.id];
      expect(find.byTooltip('화면 이동'), findsNothing);
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      viewer.transformationController!.value = Matrix4.diagonal3Values(.15, .15, 1);
      await tester.pump();
      final matrix = List<double>.of(viewer.transformationController!.value.storage);
      await tester.drag(find.byType(InteractiveViewer), const Offset(90, 60)); await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.storage, isNot(matrix));
      expect(layout.positions[record.id], before);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('layout reset requires confirmation and preserves contents and other view ($blocks)', (tester) async {
      final a = elements.add('초기화 대상'), b = elements.add('연결된 생각');
      elements.connect(a.id, {b.id});
      memoBoxes.add(MemoBox('유지할 분류', ids: [a.id]));
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      final other = blocks ? pageGraphLayout : pageGraphLayout.blockLayout;
      layout.positions[a.id] = const Offset(1700, 1700);
      layout.sizes[a.id] = const Offset(500, 400);
      other.positions[a.id] = const Offset(77, 88);
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: blocks, onChanged: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('배치 초기화')); await tester.pumpAndSettle();
      await tester.tap(find.text('취소')); await tester.pumpAndSettle();
      expect(layout.sizes[a.id], const Offset(500, 400));
      await tester.tap(find.byTooltip('배치 초기화')); await tester.pumpAndSettle();
      await tester.tap(find.text('초기화')); await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      expect(layout.sizes, isEmpty);
      expect(layout.positions[a.id], isNot(const Offset(1700, 1700)));
      expect(other.positions[a.id], const Offset(77, 88));
      expect(elements.records.length, 2);
      expect(a.connections, contains(b.id));
      expect(memoBoxes.single.elementIds, contains(a.id));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('viewport persistence accepts the supported enlarged zoom', () {
    final layout = GraphLayout()..viewport = Matrix4.diagonal3Values(8, 8, 1).storage.toList();
    expect(GraphLayout.fromJson(layout.toJson()).viewport, layout.viewport);
  });
}

import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear(); pageGraphLayout = GraphLayout(); });
  testWidgets('first thought action is hidden when the canvas has an empty box', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
    await tester.pumpAndSettle();
    expect(find.text('첫 생각 만들기'), findsOneWidget);

    memoBoxes.add(MemoBox('빈 상자'));
    elements.refreshVisibility();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('box-region-빈 상자')), findsOneWidget);
    expect(find.text('첫 생각 만들기'), findsNothing);
  });

  for (final blocks in [true]) {
    testWidgets('growing upper box escapes upward without jumping past lower box ($blocks)', (tester) async {
      final a = elements.add('커지는 위 생각'), b = elements.add('아래 생각');
      memoBoxes.addAll([MemoBox('위', ids: [a.id]), MemoBox('아래', ids: [b.id])]);
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions.addAll({a.id: const Offset(700, 700), b.id: const Offset(700, 1200)});
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      MemoBoxRegion box(String name) => tester.widget<MemoBoxRegion>(find.byKey(ValueKey('box-region-$name')));
      final upper = box('위').bounds;
      final header = tester.widget<GestureDetector>(
        find.byKey(const ValueKey('box-drag-header-아래')),
      );
      header.onPanUpdate!(DragUpdateDetails(delta: Offset(
        upper.center.dx - box('아래').bounds.center.dx,
        upper.bottom + 24.1 - box('아래').bounds.top,
      ), globalPosition: Offset.zero));
      header.onPanEnd!(DragEndDetails());
      await tester.pumpAndSettle();
      final lower = box('아래').bounds;
      layout.sizes[a.id] = Offset(blocks ? 230 : 170, blocks ? 160 : 116);
      elements.refreshVisibility(); await tester.pumpAndSettle();
      expect(box('위').bounds.center.dy, lessThan(lower.center.dy));
      expect(box('위').bounds.top, lessThan(upper.top));
      expect((box('위').bounds.center - upper.center).distance, lessThan(100));
      expect(memoBoxRegionsOverlap(box('위').bounds, box('아래').bounds), isFalse);
      expect(find.byKey(const ValueKey('canvas-boundary')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('boxes overlap during drag and separate only on release ($blocks)', (tester) async {
      final a = elements.add('첫 생각'), b = elements.add('둘째 생각');
      memoBoxes.addAll([MemoBox('첫 상자', ids: [a.id]), MemoBox('둘째 상자', ids: [b.id])]);
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions.addAll({a.id: const Offset(640, 500), b.id: const Offset(650, 510)});
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      var regions = tester.widgetList<MemoBoxRegion>(find.byType(MemoBoxRegion)).toList();
      expect(memoBoxRegionsOverlap(regions[0].bounds, regions[1].bounds), isFalse);
      regions[1].onDrag!(regions[0].bounds.center - regions[1].bounds.center);
      await tester.pumpAndSettle();
      regions = tester.widgetList<MemoBoxRegion>(find.byType(MemoBoxRegion)).toList();
      expect(memoBoxRegionsOverlap(regions[0].bounds, regions[1].bounds), isTrue);
      final stationary = regions[0].bounds;
      regions[1].onDragEnd!(); await tester.pumpAndSettle();
      regions = tester.widgetList<MemoBoxRegion>(find.byType(MemoBoxRegion)).toList();
      expect(regions[0].bounds, stationary);
      expect(memoBoxRegionsOverlap(regions[0].bounds, regions[1].bounds), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('dragging a box leaves loose thoughts in place ($blocks)', (tester) async {
      final a = elements.add('상자 안'), loose = elements.add('상자 밖');
      memoBoxes.add(MemoBox('이동 상자', ids: [a.id]));
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions.addAll({a.id: const Offset(640, 500), loose.id: const Offset(1000, 500)});
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      tester.widget<MemoBoxRegion>(find.byType(MemoBoxRegion)).onDrag!(const Offset(360, 0));
      await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      expect(layout.positions[loose.id], const Offset(1000, 500));
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('resizing preserves the edit and pushes neighboring boxes without moving loose thoughts ($blocks)', (tester) async {
      final a = elements.add('확장할 생각'), b = elements.add('이웃 생각'), loose = elements.add('미분류 생각');
      memoBoxes.addAll([MemoBox('확장 상자', ids: [a.id]), MemoBox('이웃 상자', ids: [b.id])]);
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions.addAll({a.id: const Offset(640, 500), b.id: const Offset(1100, 500), loose.id: const Offset(900, 550)});
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      final interaction = tester.widget<ThoughtInteraction>(find.ancestor(of: find.text('확장할 생각'), matching: find.byType(ThoughtInteraction)));
      interaction.onResize(const Size(640, 400), Offset.zero);
      await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
      final regions = tester.widgetList<MemoBoxRegion>(find.byType(MemoBoxRegion)).toList();
      expect(memoBoxRegionsOverlap(regions[0].bounds, regions[1].bounds), isFalse);
      expect(layout.positions[a.id], const Offset(640, 500));
      expect(layout.sizes[a.id], const Offset(640, 400));
      expect(layout.positions[b.id], isNot(const Offset(1100, 500)));
      expect(layout.positions[loose.id], const Offset(900, 550));
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('new unclassified thoughts leave existing positions intact ($blocks)', (tester) async {
      final a = elements.add('정리한 생각');
      memoBoxes.add(MemoBox('기존 상자', ids: [a.id]));
      final layout = blocks ? pageGraphLayout.blockLayout : pageGraphLayout;
      layout.positions[a.id] = const Offset(640, 500);
      final b = elements.add('새 미분류 생각');
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(layout.positions[a.id], const Offset(640, 500));
      final box = tester.widget<MemoBoxRegion>(find.byType(MemoBoxRegion));
      expect(layout.positions[b.id]!.dy, greaterThanOrEqualTo(box.bounds.bottom + 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

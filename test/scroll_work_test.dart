import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/limited_rows_wrap.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';

class _CountPaint extends CustomPainter {
  _CountPaint(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) => onPaint();
  @override
  bool shouldRepaint(covariant _CountPaint oldDelegate) => true;
}

class _CountLayout extends SingleChildRenderObjectWidget {
  const _CountLayout(this.onLayout, {required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) => _LayoutCounter(onLayout);
}
class _LayoutCounter extends RenderProxyBox {
  _LayoutCounter(this.onLayout);
  final VoidCallback onLayout;
  @override
  void performLayout() { onLayout(); super.performLayout(); }
}

void main() {
  testWidgets('desktop content switches immediately while tab highlight animates', (tester) async {
    elements.clear(); memoBoxes.clear();
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: const AllThoughtsPage(notes: [])));
    await tester.pumpAndSettle();
    final highlight = find.byKey(const ValueKey('thought-tab-highlight'));
    final start = tester.getTopLeft(highlight).dx;
    final width = tester.getSize(highlight).width;
    await tester.tap(find.text('다이어그램'));
    await tester.pump();
    expect(tester.getTopLeft(highlight).dx, closeTo(start, .1));
    expect(find.byType(ThoughtBoxView), findsNothing);
    expect(find.byType(ThoughtPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getTopLeft(highlight).dx;
    expect(middle, greaterThan(start)); expect(middle, lessThan(start + width));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getTopLeft(highlight).dx, closeTo(start + width, .1));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(ThoughtPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a thousand thoughts only mount nearby rows', (tester) async {
    elements.clear(); memoBoxes.clear();
    for (var i = 0; i < 1000; i++) { elements.add('생각 $i: 화면 밖에는 생성하지 않는 긴 메모'); }
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.android),
      home: const AllThoughtsPage(notes: [])));
    await tester.pumpAndSettle();
    expect(find.byType(LongPressDraggable<MemoDrag>).evaluate().length, lessThan(100));
    expect(find.byType(LongPressDraggable<MemoDrag>), findsWidgets);
    final search = tester.getTopLeft(find.byKey(const ValueKey('all-thoughts-search')));
    await tester.drag(find.byKey(const ValueKey('all-thoughts-grid')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byType(LongPressDraggable<MemoDrag>).evaluate().length, lessThan(100));
    expect(tester.getTopLeft(find.byKey(const ValueKey('all-thoughts-search'))), search);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    elements.clear(); memoBoxes.clear();
  });

  testWidgets('recent rows stop layout after the first hidden item and expand correctly', (tester) async {
    var layouts = 0, rows = 5;
    bool? overflow;
    late StateSetter update;
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr,
      child: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Align(alignment: Alignment.topLeft, child: SizedBox(width: 100,
          child: LimitedRowsWrap(maxRows: rows, onOverflowChanged: (value) => overflow = value,
            children: [for (var i = 0; i < 1000; i++) _CountLayout(() => layouts++,
              child: const SizedBox(width: 90, height: 30))])));
      })));
    expect(layouts, 6);
    expect(overflow, isTrue);
    expect(tester.getSize(find.byType(LimitedRowsWrap)).height, 174);
    update(() => rows = 10); await tester.pump();
    expect(layouts, lessThanOrEqualTo(17));
    expect(tester.getSize(find.byType(LimitedRowsWrap)).height, 354);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden recent rows do not issue paint calls', (tester) async {
    var paints = 0;
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 100,
        child: LimitedRowsWrap(maxRows: 2, children: [
          for (var i = 0; i < 100; i++) SizedBox(width: 90, height: 30,
            child: CustomPaint(painter: _CountPaint(() => paints++))),
        ])))));
    expect(paints, 2);
  });
}

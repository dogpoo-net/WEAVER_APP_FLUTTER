import 'package:flutter/material.dart';
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

void main() {
  testWidgets('desktop tab highlight moves over 200ms and then stops', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ThoughtBoxView), findsOneWidget);
    expect(find.byType(ThoughtPage), findsNothing);
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

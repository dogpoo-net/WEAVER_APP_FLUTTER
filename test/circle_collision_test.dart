import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  test('circle collision ignores bounding-square corners but enforces round edges', () {
    final a = Rect.fromCircle(center: Offset.zero, radius: 100);
    final diagonal = Rect.fromCircle(center: const Offset(170, 170), radius: 100);
    expect(memoBoxRegionsOverlap(a, diagonal, rectangular: true), isTrue);
    expect(memoBoxRegionsOverlap(a, diagonal, rectangular: false), isFalse);
    expect(memoBoxRegionsOverlap(a, a.shift(const Offset(210, 0)), rectangular: false), isTrue);
    expect(memoBoxRegionsOverlap(a, a.shift(const Offset(224, 0)), rectangular: false), isFalse);
  });
  testWidgets('diagonal diagram circles can occupy bounding-square corners without relocation', (tester) async {
    elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout();
    final a = elements.add('왼쪽 원'), b = elements.add('대각선 원');
    memoBoxes.addAll([MemoBox('첫 상자', ids: [a.id]), MemoBox('두 번째 상자', ids: [b.id])]);
    pageGraphLayout.positions.addAll({a.id: const Offset(640, 500), b.id: const Offset(890, 750)});
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
    await tester.pumpAndSettle(); await tester.pump(const Duration(milliseconds: 300));
    expect(pageGraphLayout.positions[b.id], const Offset(890, 750));
    final regions = tester.widgetList<MemoBoxRegion>(find.byType(MemoBoxRegion)).toList();
    expect(regions[0].bounds.overlaps(regions[1].bounds), isTrue);
    expect(memoBoxRegionsOverlap(regions[0].bounds, regions[1].bounds, rectangular: false), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}

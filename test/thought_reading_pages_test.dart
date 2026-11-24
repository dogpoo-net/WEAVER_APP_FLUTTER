import 'package:flutter/material.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('reader keeps its height and shows a chevron until the page ends', (tester) async {
    elements.clear();
    final thought = elements.add('짧은 생각');
    final long = elements.add(List.filled(60, '긴 생각').join('\n'));
    final layout = (pageGraphLayout = GraphLayout()).blockLayout;
    layout.positions.addAll({thought.id: Offset.zero, long.id: const Offset(0,32)});
    layout.layers.addAll([thought.id, long.id]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showElementMetadata(context, thought.text), child: const Text('열기'))))));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final paper = find.descendant(of: find.byKey(const ValueKey('생각읽기')), matching: find.byType(ThoughtPaperStack));
    final size = tester.getSize(paper);
    expect(size.height, lessThanOrEqualTo(size.width));
    final indicator = find.byIcon(Icons.keyboard_arrow_down);
    expect(indicator, findsNothing);
    await tester.tap(find.byTooltip('다음 페이지'));
    await tester.pumpAndSettle();
    expect(tester.getSize(paper), size);
    expect(indicator, findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.descendant(of: paper, matching: find.byType(Scrollable)).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(indicator, findsNothing);
  });

  testWidgets('link opens its stack page and edits the displayed thought', (tester) async {
    elements.clear();
    addTearDown(elements.clear);
    final thought = ElementRecord('첫 장');
    elements.records[thought.text] = thought;
    final front = elements.add('맨 위');
    final layout = (pageGraphLayout = GraphLayout()).blockLayout;
    final cards = [front, thought, elements.add('중간'), elements.add('뒤')];
    thought.extraPages.addAll(List.generate(6, (i) => ThoughtPageData('이전 페이지 $i')));
    for (var i = 0; i < cards.length; i++) {
      layout.positions[cards[i].id] = Offset(0, i * 32.0);
      layout.layers.add(cards[i].id);
    }
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
    expect(find.text('2 / 4'), findsOneWidget);
    await tap(find.byTooltip('이전 페이지'));
    expect(find.text('1 / 4'), findsOneWidget);
    await tap(find.byTooltip('수정'));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('element-editor'))).controller!.text, front.text);
    expect(find.byTooltip('다음 페이지'), findsNothing);
  });
}

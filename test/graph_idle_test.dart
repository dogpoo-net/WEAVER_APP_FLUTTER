import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout(); });

  testWidgets('a motionless graph stops work early and stays idle', (tester) async {
    elements.add('혼자 있는 생각');
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {}, onLayoutChanged: () => saves++)));
    await tester.pump(const Duration(milliseconds: 600));
    final count = saves;
    await tester.pump(const Duration(seconds: 2));
    expect(saves, count, reason: 'Zero-force nodes must not schedule updates for four seconds.');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final inBox in [false, true]) {
    testWidgets('settled nodes do not restart for metadata, links or dragging (box=$inBox)', (tester) async {
      final a = elements.add('생각 A');
      final b = elements.add('생각 B');
      final box = MemoBox('상자', ids: [a.id, b.id]); memoBoxes.add(box);
      var saves = 0;
      final layout = inBox ? box.layout : pageGraphLayout;
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(box: inBox ? box : null,
        onChanged: () {}, onLayoutChanged: () => saves++)));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final settled = Map.of(layout.positions);
      elements.update('생각 A', '생각 A 수정');
      elements.connect(a.id, [b.id]);
      await tester.pump(const Duration(milliseconds: 500));
      final count = saves;
      await tester.pump(const Duration(seconds: 2));
      expect(layout.positions, settled);
      expect(saves, count);
      await tester.drag(find.text('생각 A 수정'), const Offset(30, 20));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      final dragged = Map.of(layout.positions);
      final afterDrag = saves;
      await tester.pump(const Duration(seconds: 2));
      expect(layout.positions, dragged);
      expect(saves, afterDrag);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('covered routes and background apps stop graph work', (tester) async {
    final a = elements.add('생각 A');
    final b = elements.add('생각 B');
    final navigator = GlobalKey<NavigatorState>();
    var saves = 0;
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, navigatorObservers: [workspaceRouteObserver],
      home: ThoughtPage(onChanged: () {}, onLayoutChanged: () => saves++)));
    await tester.pump(const Duration(milliseconds: 64));
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('다른 화면'))));
    await tester.pumpAndSettle();
    final covered = Map.of(pageGraphLayout.positions);
    final count = saves;
    elements.connect(a.id, [b.id]);
    await tester.pump(const Duration(seconds: 2));
    expect(pageGraphLayout.positions, covered);
    expect(saves, count, reason: 'A covered graph must not rebuild or save on store notifications.');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final c = elements.add('새 생각');
    elements.update(c.text, c.text);
    await tester.pump(const Duration(milliseconds: 64));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = saves;
    final background = Map.of(pageGraphLayout.positions);
    await tester.pump(const Duration(seconds: 2));
    expect(saves, paused);
    expect(pageGraphLayout.positions, background);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

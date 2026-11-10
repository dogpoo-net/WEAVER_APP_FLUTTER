import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/thought_label.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/caret_assist.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear(); pageGraphLayout = GraphLayout(); });
  test('labels persist without changing connection identity, including trash', () {
    final a = elements.add('본문'); elements.add('다른 본문');
    expect(elements.update(a.text, a.text, indexLabel: ' 제목\n두줄 ', labelOnLeft: true, indexLabelColor: 0xFFFFCC80), isNull);
    expect(a.indexLabel, '제목 두줄');
    final snapshot = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
    snapshot.apply();
    final restored = elements.records['본문']!;
    expect(restored.indexLabel, '제목 두줄'); expect(restored.labelOnLeft, isTrue);
    expect(restored.indexLabelColor, 0xFFFFCC80);
    elements.remove(restored.text);
    WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).apply();
    expect(elements.trash[a.id]!.indexLabel, '제목 두줄');
  });
  testWidgets('metadata label edits apply only on save', (tester) async {
    final record = elements.add('본문');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showElementMetadata(context, record.text), child: const Text('보기'))))));
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('thought-label-editor')), '제목');
    await tester.tap(find.byKey(const ValueKey('label-left'))); await tester.pump();
    expect(record.indexLabel, isEmpty); expect(record.labelOnLeft, isFalse);
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(record.indexLabel, '제목'); expect(record.labelOnLeft, isTrue);
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('thought-label-editor')), '취소할 제목');
    await tester.tap(find.text('닫기')); await tester.pumpAndSettle();
    expect(record.indexLabel, '제목');
  });
  testWidgets('label temporarily raises a card without persisting layer changes', (tester) async {
    final a = elements.add('가려지는 본문')..indexLabel = '첫 제목';
    final b = elements.add('앞쪽 본문')..indexLabel = '둘째 제목';
    final layout = pageGraphLayout.blockLayout;
    layout.positions.addAll({a.id: const Offset(640, 400), b.id: const Offset(640, 432)});
    layout.layers.addAll([a.id, b.id]);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    final order = List<String>.of(layout.layers);
    final listener = tester.widget<Listener>(find.byKey(ValueKey('label-hold-${a.id}')));
    listener.onPointerDown!(const PointerDownEvent()); await tester.pump();
    expect(tester.widgetList<ThoughtInteraction>(find.byType(ThoughtInteraction)).last.key, ValueKey('canvas-thought-${a.id}'));
    expect(layout.layers, order);
    listener.onPointerUp!(const PointerUpEvent()); await tester.pump();
    expect(tester.widgetList<ThoughtInteraction>(find.byType(ThoughtInteraction)).last.key, ValueKey('canvas-thought-${b.id}'));
    expect(layout.layers, order);
    listener.onPointerDown!(const PointerDownEvent()); await tester.pump();
    listener.onPointerCancel!(const PointerCancelEvent()); await tester.pump();
    expect(tester.widgetList<ThoughtInteraction>(find.byType(ThoughtInteraction)).last.key, ValueKey('canvas-thought-${b.id}'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('returning to the original stack preserves the slot and highlights the target stack', (tester) async {
    final a = elements.add('첫 본문'), b = elements.add('둘째 본문'), c = elements.add('셋째 본문');
    final layout = pageGraphLayout.blockLayout;
    layout.positions.addAll({a.id: const Offset(640, 400), b.id: const Offset(640, 432), c.id: const Offset(640, 464)});
    layout.layers.addAll([a.id, b.id, c.id]);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    ThoughtInteraction card(String id) => tester.widget<ThoughtInteraction>(find.byKey(ValueKey('canvas-thought-$id')));
    final before = layout.positions[b.id], order = List<String>.of(layout.layers);
    card(b.id).onActiveChanged!(true);
    card(b.id).onMove(const Offset(10, 0)); await tester.pump();
    expect(((card(a.id).child as Card).shape as RoundedRectangleBorder).side.width, 3);
    expect(((card(c.id).child as Card).shape as RoundedRectangleBorder).side.width, 3);
    card(b.id).onDrop(Offset.zero); card(b.id).onEnd(); await tester.pumpAndSettle();
    expect(layout.positions[b.id], before); expect(layout.layers, order);
    expect(((card(a.id).child as Card).shape as RoundedRectangleBorder).side.width, 2);
    card(b.id).onActiveChanged!(true);
    card(b.id).onMove(const Offset(400, 0)); await tester.pump();
    card(b.id).onMove(const Offset(-400, 0)); await tester.pump();
    card(b.id).onDrop(Offset.zero); card(b.id).onEnd(); await tester.pumpAndSettle();
    expect(layout.positions[b.id], before); expect(layout.layers, order);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('labels grow with their text', (tester) async {
    final a = elements.add('짧음')..indexLabel = '가';
    final b = elements.add('김')..indexLabel = '길이에 맞추어 늘어나는 라벨';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => Column(children: [
      for (final record in [a, b]) SizedBox(width: ThoughtLabel.width(context, record.indexLabel),
        child: ThoughtLabel(key: ValueKey(record.id), record: record, onHold: (_) {})),
    ])))));
    expect(tester.getSize(find.byKey(ValueKey(a.id))).width, lessThan(tester.getSize(find.byKey(ValueKey(b.id))).width));
    expect(tester.takeException(), isNull);
  });
  testWidgets('selection drag snaps onto another thought', (tester) async {
    tester.view.physicalSize = const Size(1200, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final a = elements.add('움직일 생각'), b = elements.add('붙일 생각');
    final layout = pageGraphLayout.blockLayout;
    layout.positions.addAll({a.id: const Offset(500, 400), b.id: const Offset(850, 400)});
    layout.viewport = (Matrix4.identity()..setTranslationRaw(-300, -200, 0)).storage.toList();
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택')); await tester.pumpAndSettle();
    final overlay = tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));
    final gesture = await tester.startGesture(overlay.localToGlobal(const Offset(570, 440)));
    await gesture.moveBy(const Offset(30, 0)); await tester.pump();
    await gesture.moveTo(overlay.localToGlobal(const Offset(920, 440))); await tester.pump();
    await gesture.up(); await tester.pumpAndSettle();
    expect(layout.positions[a.id], const Offset(850, 432));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('selection drag assigns an empty memo box', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final record = elements.add('상자에 넣을 메모');
    final box = MemoBox('목적 상자'); memoBoxes.add(box);
    pageGraphLayout.blockLayout.positions[record.id] = const Offset(500, 400);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택')); await tester.pumpAndSettle();
    final overlay = tester.renderObject<RenderBox>(find.byKey(const ValueKey('canvas-selection')));
    final region = tester.widget<MemoBoxRegion>(find.byKey(const ValueKey('box-region-목적 상자')));
    final start = overlay.localToGlobal(pageGraphLayout.blockLayout.positions[record.id]! + const Offset(70, 40));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(30, 0)); await tester.pump();
    await gesture.moveTo(overlay.localToGlobal(region.bounds.center)); await tester.pump();
    await gesture.up(); await tester.pumpAndSettle();
    expect(box.elementIds, contains(record.id));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('assist searches titles but returns the original thought identity', (tester) async {
    final a = elements.add('검색어와 다른 본문')..indexLabel = '라벨 제목';
    final controller = TextEditingController(), focus = FocusNode();
    String? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(controller: controller, focus: focus,
      words: elements.visibleWords, useThoughtLabels: true, onWord: (word) => chosen = word,
      child: TextField(controller: controller, focusNode: focus)))));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '라벨'); await tester.pumpAndSettle();
    final suggestion = find.byKey(ValueKey('suggestion-${a.text}'));
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion); await tester.pumpAndSettle();
    expect(chosen, a.text);
    await tester.pumpWidget(const SizedBox()); controller.dispose(); focus.dispose();
  });
}

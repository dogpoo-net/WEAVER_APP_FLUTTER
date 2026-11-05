import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(() {
    elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout();
    SharedPreferences.setMockInitialValues({});
  });

  test('layouts persist independently in the existing browser snapshot', () async {
    final r = elements.add('같은 생각');
    pageGraphLayout.positions[r.id] = const Offset(100, 200);
    pageGraphLayout.viewport = (Matrix4.identity()..setTranslationRaw(20, 30, 0)).storage.toList();
    final a = MemoBox('상자 A', ids: [r.id]);
    final b = MemoBox('상자 B', ids: [r.id]);
    a.layout.positions[r.id] = const Offset(300, 400);
    b.layout.positions[r.id] = const Offset(500, 600);
    a.layout.tags['tag:독서'] = const Offset(700, 800);
    memoBoxes.addAll([a, b]);
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await storage.write(WorkspaceSnapshot.encode([]));
    pageGraphLayout = GraphLayout(); memoBoxes.clear(); elements.clear();
    WorkspaceSnapshot.decode(storage.read()!).apply();
    expect(pageGraphLayout.positions[r.id], const Offset(100, 200));
    expect(pageGraphLayout.viewport![12], 20);
    expect(memoBoxes[0].layout.positions[r.id], const Offset(300, 400));
    expect(memoBoxes[1].layout.positions[r.id], const Offset(500, 600));
    expect(memoBoxes[0].layout.tags['tag:독서'], const Offset(700, 800));

    final legacy = jsonDecode(storage.read()!) as Map<String, dynamic>;
    legacy.remove('graphLayout');
    for (final box in legacy['memoBoxes'] as List) { (box as Map).remove('layout'); }
    WorkspaceSnapshot.decode(jsonEncode(legacy)).apply();
    expect(pageGraphLayout.positions, isEmpty);
    expect(memoBoxes.every((box) => box.layout.positions.isEmpty), isTrue);
    expect(elements.records.length, 1);
    expect(GraphLayout.fromJson({'viewport': Matrix4.diagonal3Values(.8, .8, .8).storage.toList()}).viewport, isNotNull);
    expect(GraphLayout.fromJson({'viewport': [1, 2], 'positions': {'bad': ['x', 2]}}).positions, isEmpty);
  });

  for (final inBox in [false, true]) {
    testWidgets('reopen restores nodes, tags and viewport without layout drift (box=$inBox)', (tester) async {
      final a = elements.add('생각 A #독서');
      final b = elements.add('생각 B');
      final box = MemoBox('내 상자', ids: [a.id, b.id]);
      memoBoxes.add(box);
      String? saved;
      void persist() => saved = WorkspaceSnapshot.encode([]);
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(box: inBox ? box : null, onChanged: persist)));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('graph-tag-독서')), const Offset(55, -35));
      await tester.pumpAndSettle();
      await tester.drag(find.text('생각 A'), const Offset(30, 45));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      viewer.transformationController!.value = Matrix4.diagonal3Values(.7, .7, 1)..setTranslationRaw(-650, -450, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(saved, isNotNull);
      final layout = inBox ? box.layout : pageGraphLayout;
      final positions = Map.of(layout.positions);
      final tags = Map.of(layout.tags);
      final matrix = List.of(layout.viewport!);
      await tester.pumpWidget(const SizedBox());
      WorkspaceSnapshot.decode(saved!).apply();
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(box: inBox ? memoBoxes.single : null, onChanged: persist)));
      await tester.pumpAndSettle();
      final restored = inBox ? memoBoxes.single.layout : pageGraphLayout;
      expect(restored.positions, positions);
      expect(restored.tags, tags);
      expect(tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.storage, matrix);
      await tester.enterText(find.byKey(const ValueKey('graph-search')), '생각 B');
      await tester.pumpAndSettle();
      expect(restored.positions[a.id], positions[a.id]);
      await tester.enterText(find.byKey(const ValueKey('graph-search')), '');
      await tester.pumpAndSettle();
      expect(restored.positions, positions);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

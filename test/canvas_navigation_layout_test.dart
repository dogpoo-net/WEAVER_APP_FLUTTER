import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('menu box filter and overview use the same saved canvas', (tester) async {
    SharedPreferences.setMockInitialValues({});
    elements.clear();
    memoBoxes.clear();
    pageGraphLayout = GraphLayout();
    final record = elements.add('정리한 메모');
    final box = MemoBox('내 상자', ids: [record.id]);
    memoBoxes.add(box);
    const position = Offset(1400, 900);
    pageGraphLayout.blockLayout.positions[record.id] = position;
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(
      notes: const [], initialBox: box, storage: storage,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '메모상자'));
    await tester.pumpAndSettle();
    final canvas = tester.widget<ThoughtPage>(find.byType(ThoughtPage));
    expect(canvas.box, isNull, reason: 'A menu selection is a filter, not a separate layout owner');
    expect(pageGraphLayout.blockLayout.positions[record.id], position);
    expect(box.layout.blockLayout.positions, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, '생각'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '메모상자'));
    await tester.pumpAndSettle();
    expect(pageGraphLayout.blockLayout.positions[record.id], position);
    await tester.pumpWidget(const SizedBox());
    final saved = WorkspaceSnapshot.encode([]);
    WorkspaceSnapshot.decode(saved).apply();
    expect(pageGraphLayout.blockLayout.positions[record.id], position);
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(
      notes: const [], initialView: ThoughtView.page, storage: storage,
    )));
    await tester.pumpAndSettle();
    expect(pageGraphLayout.blockLayout.positions[record.id], position);
    await tester.pumpWidget(const SizedBox());
  });
}

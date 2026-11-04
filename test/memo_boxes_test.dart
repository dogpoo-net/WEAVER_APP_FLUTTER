import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';

void main() {
  setUp(() { memoBoxes.clear(); elements.clear(); });
  test('box membership and labels survive restore with stable element identity', () {
    final record = elements.add('보관할 메모');
    memoBoxes.add(MemoBox('자료', color: 0xFF64B5F6, ids: [record.id]));
    final data = WorkspaceSnapshot.encode([]);
    memoBoxes.clear();
    WorkspaceSnapshot.decode(data).apply();
    expect(memoBoxes.single.name, '자료');
    expect(memoBoxes.single.color, 0xFF64B5F6);
    expect(memoBoxes.single.elementIds, {record.id});
  });
  testWidgets('picker adds existing memo and removal preserves original', (tester) async {
    final record = elements.add('보관할 메모');
    final box = MemoBox('자료');
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: MemoBoxPage(box: box, onChanged: () => saves++)));
    await tester.tap(find.byTooltip('메모 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('담기'));
    await tester.pumpAndSettle();
    expect(box.elementIds, {record.id});
    await tester.tap(find.byTooltip('상자에서 빼기'));
    await tester.pumpAndSettle();
    expect(box.elementIds, isEmpty);
    expect(elements.records.containsKey(record.text), isTrue);
    expect(saves, 2);
  });
  testWidgets('mobile zoom supports six columns and drag adds to box', (tester) async {
    final record = elements.add('보관할 메모');
    final box = MemoBox('자료'); memoBoxes.add(box);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.android),
      home: const AllThoughtsPage(notes: [])));
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.byTooltip('축소'));
      await tester.tap(find.byTooltip('축소')); await tester.pumpAndSettle();
    }
    expect(find.text('6열'), findsOneWidget);
    final tile = find.byKey(ValueKey('thought-${record.id}'));
    await tester.ensureVisible(tile);
    final gesture = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.byType(MemoBoxTarget)));
    await tester.pump(); await gesture.up(); await tester.pumpAndSettle();
    expect(box.elementIds, {record.id});
    expect(tester.takeException(), isNull);
  });
}

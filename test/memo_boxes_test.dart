import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';

void main() {
  setUp(() { memoBoxes.clear(); memoBoxFolders.clear(); elements.clear(); });
  test('existing unclassified box becomes the default without duplicate labels', () {
    final record = elements.add('기존 미분류 생각');
    final legacy = MemoBox('미분류', color: 0xFF64B5F6, ids: [record.id]);
    memoBoxes.add(legacy);
    final box = ensureUnclassifiedBox();
    expect(memoBoxes, [box]);
    expect(box.isUnclassified, isTrue);
    expect(box.color, legacy.color);
    expect(box.layout, same(legacy.layout));
    expect(box.elementIds, {record.id});
  });
  test('unclassified follows membership and survives restore', () {
    final record = elements.add('분류할 생각');
    final unclassified = ensureUnclassifiedBox();
    final box = MemoBox('자료'); memoBoxes.add(box);
    expect(unclassified.elementIds, {record.id});
    moveThoughtToBox(record.id, box);
    expect(unclassified.elementIds, isEmpty);
    moveThoughtToBox(record.id, unclassified);
    expect(box.elementIds, isEmpty);
    expect(unclassified.elementIds, {record.id});
    WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).apply();
    expect(ensureUnclassifiedBox().elementIds, {record.id});
    expect(memoBoxes.where((box) => box.isUnclassified), hasLength(1));
  });
  test('moving a thought replaces membership and restore removes legacy duplicates', () {
    final record = elements.add('단일 소속');
    final first = MemoBox('첫 상자', ids: [record.id]);
    final second = MemoBox('둘째 상자');
    memoBoxes.addAll([first, second]);
    moveThoughtToBox(record.id, second);
    expect(first.elementIds, isEmpty);
    expect(second.elementIds, {record.id});
    first.elementIds.add(record.id);
    WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).apply();
    expect(memoBoxes.where((box) => box.elementIds.contains(record.id)).length, 1);
  });
  test('box membership and labels survive restore with stable element identity', () {
    final record = elements.add('보관할 메모');
    memoBoxFolders.add('분류');
    memoBoxes.add(MemoBox('자료', color: 0xFF64B5F6, folder: '분류', ids: [record.id]));
    final data = WorkspaceSnapshot.encode([]);
    memoBoxes.clear();
    WorkspaceSnapshot.decode(data).apply();
    expect(memoBoxes.single.name, '자료');
    expect(memoBoxes.single.folder, '분류');
    expect(memoBoxFolders, ['분류']);
    expect(memoBoxes.single.color, 0xFF64B5F6);
    expect(memoBoxes.single.elementIds, {record.id});
  });
  testWidgets('filtered box has no bulk membership picker', (tester) async {
    final box = MemoBox('자료');
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(initialView: ThoughtView.boxes, notes: const [], initialBox: box)));
    expect(find.byTooltip('상자에 담을 메모 선택'), findsNothing);
    expect(find.byIcon(Icons.playlist_add), findsNothing);
  });
  testWidgets('mobile zoom reduces badge width and drag adds to box', (tester) async {
    final record = elements.add('보관할 메모');
    final box = MemoBox('자료'); memoBoxes.add(box);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.android),
      home: const AllThoughtsPage(initialView: ThoughtView.boxes, notes: [])));
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.byTooltip('축소'));
      await tester.tap(find.byTooltip('축소')); await tester.pumpAndSettle();
    }
    expect(find.text('33%'), findsOneWidget);
    final tile = find.byKey(ValueKey('thought-${record.id}'));
    await tester.ensureVisible(tile);
    final gesture = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.byWidgetPredicate((w) => w is MemoBoxTarget && identical(w.box, box))));
    await tester.pump(); await gesture.up(); await tester.pumpAndSettle();
    expect(box.elementIds, {record.id});
    expect(tester.takeException(), isNull);
  });
}

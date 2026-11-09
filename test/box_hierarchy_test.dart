import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); pageGraphLayout = GraphLayout(); });
  test('three levels persist, preserve exclusive membership, reject cycles and excess depth', () {
    final record = elements.add('하위 메모');
    final root = MemoBox('큰 상자'), child = MemoBox('중간'), leaf = MemoBox('작은'), extra = MemoBox('추가');
    memoBoxes.addAll([root, child, leaf, extra]);
    setBoxParent(child, root); setBoxParent(leaf, child);
    expect(leaf.depth, 3);
    expect(() => setBoxParent(extra, leaf), throwsArgumentError);
    expect(() => setBoxParent(root, leaf), throwsArgumentError);
    expect(() => setBoxParent(child, child), throwsArgumentError);
    moveThoughtToBox(record.id, leaf);
    expect(root.elementIds, isEmpty); expect(root.subtreeElementIds, {record.id});
    final restored = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
    restored.apply();
    final loaded = memoBoxes.singleWhere((b) => b.name == '작은');
    expect(loaded.depth, 3); expect(loaded.path, '큰 상자 / 중간 / 작은');
    expect(loaded.elementIds, {record.id});
  });
  testWidgets('nested rectangles enclose children and drag together', (tester) async {
    final record = elements.add('작은 상자 안');
    final root = MemoBox('상위'), child = MemoBox('중간', parentName: '상위'), leaf = MemoBox('하위', parentName: '중간', ids: [record.id]);
    memoBoxes.addAll([root, child, leaf]);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    MemoBoxRegion region(String name) => tester.widget<MemoBoxRegion>(find.byKey(ValueKey('box-region-$name')));
    final outer = region('상위').bounds, middle = region('중간').bounds, inner = region('하위').bounds;
    expect(outer.contains(middle.topLeft), isTrue); expect(outer.contains(middle.bottomRight), isTrue);
    expect(middle.contains(inner.topLeft), isTrue); expect(middle.contains(inner.bottomRight), isTrue);
    region('상위').onDrag!(const Offset(40, 30)); await tester.pumpAndSettle();
    expect(region('하위').bounds.topLeft, inner.topLeft + const Offset(40, 30));
    expect(find.byTooltip('메모상자 구조'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_folder_region.dart';
import 'package:weaver/features/inbox/memo_box_region.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear(); pageGraphLayout = GraphLayout(); });
  test('folder tree persists independently of box and thought ownership', () {
    final thought = elements.add('상자에만 담긴 생각');
    memoBoxFolders.addAll(['부모', '자식', '손자']);
    moveMemoFolder('자식', '부모'); moveMemoFolder('손자', '자식');
    memoBoxes.add(MemoBox('자료', folder: '손자', ids: [thought.id]));
    expect(() => moveMemoFolder('부모', '손자'), throwsArgumentError);
    final snapshot = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
    memoBoxFolderParents.clear(); snapshot.apply();
    expect(memoFolderPath('손자'), '부모 / 자식 / 손자');
    expect(memoBoxes.singleWhere((b) => b.name == '자료').elementIds, {thought.id});
    moveMemoFolder('자식', null); expect(memoFolderPath('손자'), '자식 / 손자');
  });
  testWidgets('menu folder drops change shared data and reject descendants', (tester) async {
    memoBoxFolders.addAll(['부모', '자식']); var changes = 0;
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux), home: Scaffold(
      body: WorkspaceMenu(embedded: true, projects: const [], onBoxChanged: () => changes++))));
    await tester.pumpAndSettle();
    final target = tester.widget<DragTarget<MemoFolderDrag>>(find.byKey(const ValueKey('drop-folder-부모')));
    const details = DragTargetDetails(data: MemoFolderDrag('자식'), offset: Offset.zero);
    expect(target.onWillAcceptWithDetails!(details), isTrue);
    target.onAcceptWithDetails!(details); await tester.pumpAndSettle();
    expect(memoFolderParent('자식'), '부모'); expect(changes, 1);
    expect(canMoveMemoFolder('부모', '자식'), isFalse);
    final outside = tester.widget<DragTarget<MemoFolderDrag>>(find.byKey(const ValueKey('drop-folder-outside')));
    outside.onAcceptWithDetails!(details); await tester.pumpAndSettle();
    expect(memoFolderParent('자식'), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('folder canvas encloses shared boxes but never owns thoughts', (tester) async {
    final thought = elements.add('자료 메모'), loose = elements.add('폴더에 넣을 수 없는 메모');
    memoBoxFolders.addAll(['상위', '하위']); moveMemoFolder('하위', '상위');
    final box = MemoBox('자료', folder: '하위', ids: [thought.id]); memoBoxes.add(box);
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
    await tester.pumpAndSettle();
    final outer = tester.widget<MemoFolderRegion>(find.byKey(const ValueKey('folder-region-상위')));
    final inner = tester.widget<MemoFolderRegion>(find.byKey(const ValueKey('folder-region-하위')));
    final region = tester.widget<MemoBoxRegion>(find.byKey(const ValueKey('box-region-자료')));
    expect(outer.bounds.contains(inner.bounds.topLeft), isTrue);
    expect(inner.bounds.contains(region.bounds.topLeft), isTrue);
    expect(find.descendant(of: find.byType(MemoFolderRegion), matching: find.byType(DragTarget<MemoDrag>)), findsNothing);
    outer.onMove(const Offset(40, 30)); await tester.pumpAndSettle();
    final moved = tester.widget<MemoBoxRegion>(find.byKey(const ValueKey('box-region-자료')));
    expect(moved.bounds.topLeft, region.bounds.topLeft + const Offset(40, 30));
    expect(box.elementIds, {thought.id});
    expect(memoBoxes.any((b) => !b.isUnclassified && b.elementIds.contains(loose.id)), isFalse);
    expect(memoBoxes.where((b) => !b.isUnclassified).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

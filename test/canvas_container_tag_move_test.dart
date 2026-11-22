import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  for (final folder in [false, true]) {
    for (final lift in [false, true]) {
      testWidgets('selected tag follows container folder=$folder lift=$lift', (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear();
        pageGraphLayout = GraphLayout();
        final a = elements.add('메모')..tags.addAll(['선택', '고정']);
        memoBoxes.add(MemoBox('상자', ids: [a.id], folder: folder ? '폴더' : null));
        if (folder) memoBoxFolders.add('폴더');
        final layout = pageGraphLayout.blockLayout;
        layout.positions[a.id] = const Offset(500, 500);
        layout.tags.addAll({'tag:선택': const Offset(950, 500), 'tag:고정': const Offset(950, 750)});
        layout.viewport = (Matrix4.identity()..setTranslationRaw(-300,-300,0)).storage.toList();
        await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged:(){})));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft); await tester.pump();
        await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('graph-tag-선택')))); await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft); await tester.pump();
        final before = layout.positions[a.id]!;
        final tag = layout.tags['tag:선택']!;
        final fixed = layout.tags['tag:고정']!;
        final start = folder
            ? tester.getTopLeft(find.byKey(const ValueKey('folder-region-폴더'))) + const Offset(50,20)
            : tester.getTopLeft(find.byKey(const ValueKey('box-drag-header-상자'))) + const Offset(10,16);
        final gesture = await tester.startGesture(start);
        if (lift) await tester.pump(const Duration(milliseconds:600));
        await gesture.moveBy(const Offset(60,40)); await tester.pump();
        await gesture.moveBy(const Offset(100,80)); await tester.pump();
        await gesture.up(); await tester.pumpAndSettle();
        final shift = layout.positions[a.id]! - before;
        expect(shift.distance, greaterThan(30));
        expect(layout.tags['tag:선택']! - tag, shift);
        expect(layout.tags['tag:고정'], fixed);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

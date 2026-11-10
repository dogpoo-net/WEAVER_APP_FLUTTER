import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/memo_folder_region.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  for (final selection in [false, true]) {
    testWidgets('two fingers zoom over a folder with selection=$selection', (tester) async {
      elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); pageGraphLayout = GraphLayout();
      memoBoxFolders.add('폴더');
      final layout = pageGraphLayout.blockLayout;
      layout.folderPositions['폴더'] = const Offset(500, 500);
      layout.viewport = (Matrix4.identity()..setTranslationRaw(-400, -350, 0)).storage.toList();
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(blocks: true, onChanged: () {})));
      await tester.pumpAndSettle();
      if (selection) { await tester.tap(find.text('선택')); await tester.pumpAndSettle(); }
      final top = tester.getTopLeft(find.byType(MemoFolderRegion));
      final left = top + const Offset(70, 110), right = top + const Offset(230, 110);
      final a = await tester.startGesture(left, pointer: 1);
      final b = await tester.startGesture(right, pointer: 2);
      for (var i = 1; i <= 4; i++) {
        await a.moveTo(left - Offset(i * 12, 0));
        await b.moveTo(right + Offset(i * 12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up(); await b.up(); await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(layout.folderPositions['폴더'], const Offset(500, 500));
      await tester.pumpWidget(const SizedBox());
      memoBoxFolders.clear();
    });
  }
}

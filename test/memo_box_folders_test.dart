import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  setUp(() { memoBoxes.clear(); memoBoxFolders.clear(); });
  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets('box moves into and out of folder ($platform)', (tester) async {
      tester.view.physicalSize = const Size(1200, 1100); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      memoBoxes.add(MemoBox('자료')); memoBoxFolders.add('분류');
      var changes = 0;
      int? choice;
      await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: platform), home: Scaffold(
        body: WorkspaceMenu(embedded: true, projects: const [], onBoxChanged: () => changes++, onSelected: (value) => choice = value))));
      await tester.tap(find.byTooltip('메모상자 폴더 만들기'));
      expect(choice, WorkspaceMenu.createBoxFolder);
      Future<void> move(Finder target) async {
        final source = find.byKey(const ValueKey('menu-box-0'));
        await tester.ensureVisible(source); await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tester.getCenter(source));
        if (platform == TargetPlatform.android) await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(tester.getCenter(target)); await tester.pump();
        await gesture.up(); await tester.pumpAndSettle();
      }
      await move(find.byKey(const ValueKey('drop-box-분류')));
      expect(memoBoxes.single.folder, '분류');
      await tester.tap(find.text('분류')); await tester.pumpAndSettle();
      await move(find.byKey(const ValueKey('drop-box-outside')));
      expect(memoBoxes.single.folder, isNull);
      expect(changes, 2);
      final separator = tester.widget<Divider>(find.byKey(const ValueKey('section-divider-box')));
      expect(separator.thickness, 1);
      expect(separator.indent, 20);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  testWidgets('projects move out through section gaps without changing font size', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final projectMoves = <String?>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkspaceMenu(
      embedded: true, projects: const ['프로젝트 글'],
      folders: const ['프로젝트 폴더'], projectFolderNames: const ['프로젝트 폴더'],
      onProjectMoved: (index, folder) => projectMoves.add(folder),
    ))));
    await tester.tap(find.text('프로젝트 폴더'));
    await tester.pumpAndSettle();
    final nestedProjectX = tester.getTopLeft(find.text('프로젝트 글')).dx;
    expect(tester.widget<Text>(find.text('프로젝트 글')).style!.fontSize, 13);
    Future<void> move(String item, String gap) async {
      final source = find.byKey(ValueKey(item));
      final target = find.byKey(ValueKey(gap));
      expect(tester.getSize(target).height, 14);
      if (Theme.of(tester.element(source)).platform == TargetPlatform.android) {
        final drag = await tester.startGesture(tester.getCenter(source));
        await tester.pump(const Duration(milliseconds: 600));
        await drag.moveTo(tester.getCenter(target));
        await tester.pump();
        await drag.up();
      } else {
        await tester.dragFrom(tester.getCenter(source), tester.getCenter(target) - tester.getCenter(source));
      }
      await tester.pumpAndSettle();
    }
    await move('menu-project-0', 'drop-box-outside');
    expect(projectMoves, isEmpty);
    await move('menu-project-0', 'drop-project-outside');
    expect(projectMoves, [null]);
    expect(tester.widget<Text>(find.text('프로젝트 글')).style!.fontSize, 13);
    expect(tester.getTopLeft(find.text('프로젝트 글')).dx, lessThan(nestedProjectX));
    expect(find.text('미분류'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.android}));
}

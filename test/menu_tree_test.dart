import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  testWidgets('folder children are indented, smaller and open over 200ms without borders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 320, child: WorkspaceMenu(
      embedded: true, folders: ['폴더'], projects: ['폴더 안 프로젝트', '바깥 프로젝트'], projectFolderNames: ['폴더', null],
    )))));
    expect(find.text('미분류'), findsNothing);
    await tester.tap(find.text('폴더'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final halfway = tester.getTopLeft(find.text('바깥 프로젝트')).dy;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('바깥 프로젝트')).dy, greaterThan(halfway));
    expect(tester.getTopLeft(find.text('폴더 안 프로젝트')).dx, greaterThan(tester.getTopLeft(find.text('바깥 프로젝트')).dx));
    expect(tester.widget<Text>(find.text('폴더 안 프로젝트')).style!.fontSize, 13);
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect((tile.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hashtag heading pins to menu viewport while its items keep scrolling', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 320, child: WorkspaceMenu(
      embedded: true, projects: List.generate(12, (i) => '프로젝트$i'), tags: List.generate(30, (i) => '태그$i'),
    )))));
    final scroll = find.byKey(const ValueKey('menu-projects'));
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    controller.jumpTo(1000);
    await tester.pumpAndSettle();
    final heading = find.byKey(const ValueKey('menu-tags-heading'));
    // Section sizes can change; scroll until this heading actually reaches the viewport.
    final distance = tester.getRect(heading).top - tester.getRect(scroll).top;
    if (distance > 0) {
      controller.jumpTo(controller.offset + distance);
      await tester.pumpAndSettle();
    }
    expect(tester.getRect(heading).top, closeTo(tester.getRect(scroll).top, 1));
    final item = find.byKey(const ValueKey('menu-tag-5'));
    final before = tester.getTopLeft(item).dy;
    controller.jumpTo(controller.offset + 50);
    await tester.pumpAndSettle();
    expect(tester.getRect(heading).top, closeTo(tester.getRect(scroll).top, 1));
    expect(tester.getTopLeft(item).dy, lessThan(before));
    expect(tester.takeException(), isNull);
  });
}

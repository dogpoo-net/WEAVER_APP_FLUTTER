import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/desktop_menu_frame.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';

void main() {
  testWidgets('desktop menu stays pinned across views and floats only on request', (tester) async {
    tester.view.physicalSize = const Size(1420, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp()); await tester.pumpAndSettle();
    final menu = find.byType(WorkspaceMenu);
    await tester.tap(find.descendant(of: menu, matching: find.text('모든 생각 보기')));
    await tester.pumpAndSettle();
    expect(find.byType(AllThoughtsPage), findsOneWidget);
    expect(tester.widget<WorkspaceMenu>(menu).embedded, isTrue);
    expect(tester.getTopLeft(menu).dx, 0);
    expect(tester.getSize(find.byType(AppBar)).width, 1420);
    expect(tester.getTopLeft(menu).dy, greaterThanOrEqualTo(tester.getBottomRight(find.byType(AppBar)).dy));
    final pinnedWidth = tester.getSize(find.byType(DesktopMenuBody)).width - tester.getSize(menu).width;
    await tester.tap(find.text('상자')); await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceMenu>(menu).embedded, isTrue);
    expect(find.byTooltip('메뉴 숨기기'), findsNothing);
    expect(find.byTooltip('메뉴를 모달로 보기'), findsNothing);
    await tester.tap(find.text('WEAVER')); await tester.pumpAndSettle();
    expect(find.byType(AllThoughtsPage), findsNothing);
    await tester.tap(find.byTooltip('메뉴 숨기기')); await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(tester.getSize(find.byType(DesktopMenuBody)).width, greaterThan(pinnedWidth));
    await tester.tap(find.byTooltip('메뉴 열기')); await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceMenu>(menu).embedded, isFalse);
    expect(find.byTooltip('메뉴 고정하기'), findsNothing);
    expect(find.byTooltip('메뉴 닫기'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home navigation respects an unsaved project', (tester) async {
    tester.view.physicalSize = const Size(1420, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp()); await tester.pumpAndSettle();
    await tester.tap(find.text('프로젝트 생성')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('project-document')), '계속 쓸 본문');
    await tester.pump();
    await tester.tap(find.text('WEAVER')); await tester.pumpAndSettle();
    expect(find.text('변경 내용을 저장하지 않고 나갈까요?'), findsOneWidget);
    await tester.tap(find.text('계속 작성')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, '계속 쓸 본문');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

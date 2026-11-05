import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  testWidgets('desktop menu hides into left modal and pins again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    expect(
      tester.widget<WorkspaceMenu>(find.byType(WorkspaceMenu)).embedded,
      isTrue,
    );
    await tester.tap(find.byTooltip('메뉴 숨기기').first);
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceMenu), findsNothing);
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WorkspaceMenu>(find.byType(WorkspaceMenu)).embedded,
      isFalse,
    );
    expect(tester.getTopLeft(find.byType(Dialog)).dx, lessThan(100));
    await tester.tap(find.byTooltip('메뉴 고정하기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WorkspaceMenu>(find.byType(WorkspaceMenu)).embedded,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu separates browsing categories and paragraph writing stays on main', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    expect(find.text('메인'), findsOneWidget);
    expect(find.descendant(of: find.byType(WorkspaceMenu), matching: find.text('문단 쓰기')), findsNothing);
    await tester.tap(find.byTooltip('메뉴 닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('페이지'));
    await tester.pumpAndSettle();
    expect(find.text('생각 만들기'), findsNothing);
    expect(find.byTooltip('생각 만들기'), findsOneWidget);
  });
  testWidgets('only project list scrolls while navigation remains fixed', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<int>(
                  context: context,
                  builder: (_) => WorkspaceMenu(
                    projects: List.generate(30, (i) => '프로젝트 $i'),
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('메인'));
    await tester.scrollUntilVisible(
      find.text('프로젝트 29'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('menu-projects')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.getTopLeft(find.text('메인')), before);
    await tester.ensureVisible(find.text('프로젝트 29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('프로젝트 29'));
    await tester.pumpAndSettle();
    expect(selected, 29);
  });
}

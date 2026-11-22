import 'package:weaver/features/inbox/element_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  testWidgets(
    'menu opens document and thought tabs and expands boxes by level',
    (tester) async {
      memoBoxes
        ..clear()
        ..addAll([
          MemoBox('프로젝트'),
          MemoBox('인터뷰', folder: '프로젝트'),
          MemoBox('후속 인터뷰', folder: '인터뷰'),
        ]);
      addTearDown(memoBoxes.clear);
      elements.clear();
      elements.add('첫 생각 #여행');
      elements.add('둘째 생각 #여행');
      addTearDown(elements.clear);
      final selections = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceMenu(
              embedded: true,
              projects: const [],
              tags: const ['여행'],
              onSelected: selections.add,
              onRename: (_, oldName, newName) async {
                memoBoxes.singleWhere((box) => box.name == oldName).name = newName;
              },
              onDeleteBox: (_, _) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('문서'));
      await tester.tap(find.text('생각'));
      expect(selections, [WorkspaceMenu.documents, WorkspaceMenu.thoughts]);
      expect(find.text('프로젝트'), findsNothing);

      await tester.tap(find.text('메모상자'));
      await tester.pumpAndSettle();
      expect(find.text('프로젝트'), findsOneWidget);
      expect(selections, [WorkspaceMenu.documents, WorkspaceMenu.thoughts]);
      expect(find.text('인터뷰'), findsNothing);

      await tester.tap(find.text('프로젝트'));
      await tester.pumpAndSettle();
      expect(find.text('인터뷰'), findsOneWidget);
      expect(find.text('후속 인터뷰'), findsNothing);
      await tester.tap(find.text('인터뷰'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('후속 인터뷰'));
      expect(selections.last, WorkspaceMenu.boxChoice(2));

      await tester.tap(find.byTooltip('후속 인터뷰 관리'));
      await tester.pumpAndSettle();
      expect(find.text('상자 삭제'), findsOneWidget);
      await tester.tap(find.text('이름 변경'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '인터뷰 자료');
      await tester.tap(find.text('변경'));
      await tester.pumpAndSettle();
      expect(find.text('인터뷰 자료'), findsOneWidget);
      expect(find.text('#여행'), findsNothing);
      await tester.tap(find.text('해시태그'));
      expect(selections.last, WorkspaceMenu.hashtags);
    },
  );
}

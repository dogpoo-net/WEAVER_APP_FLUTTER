import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/features/inbox/project_folders.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  test('hashtag folders round trip and legacy backups remain readable', () {
    elements.clear();
    projectFolders.clear();
    hashtagFolders
      ..clear()
      ..addAll(['독서', '빈 폴더']);
    hashtagFolderAssignments
      ..clear()
      ..['책'] = '독서';
    final json = WorkspaceSnapshot.encode([]);
    hashtagFolders.clear();
    hashtagFolderAssignments.clear();
    WorkspaceSnapshot.decode(json).apply();
    expect(hashtagFolders, ['독서', '빈 폴더']);
    expect(hashtagFolderAssignments, {'책': '독서'});
    final old = jsonDecode(json) as Map<String, dynamic>;
    old.remove('hashtagFolders');
    old.remove('hashtagFolderAssignments');
    WorkspaceSnapshot.decode(jsonEncode(old)).apply();
    expect(hashtagFolders, isEmpty);
    expect(hashtagFolderAssignments, isEmpty);
  });
  testWidgets(
    'project and tag drag into folders and back to unfiled',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final projectMoves = <String?>[];
      final tagMoves = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceMenu(
              embedded: true,
              projects: const ['글'],
              tags: const ['책'],
              folders: const ['프로젝트 폴더'],
              tagFolders: const ['태그 폴더'],
              onProjectMoved: (i, f) {
                expect(i, 0);
                projectMoves.add(f);
              },
              onTagMoved: (t, f) {
                expect(t, '책');
                tagMoves.add(f);
              },
            ),
          ),
        ),
      );
      Future<void> move(String item, String target) async {
        final source = find.byKey(ValueKey(item));
        final destination = find.byKey(ValueKey(target));
        if (Theme.of(tester.element(find.byType(WorkspaceMenu))).platform ==
            TargetPlatform.android) {
          final gesture = await tester.startGesture(tester.getCenter(source));
          await tester.pump(const Duration(milliseconds: 600));
          await gesture.moveTo(tester.getCenter(destination));
          await tester.pump();
          await gesture.up();
        } else {
          await tester.dragFrom(
            tester.getCenter(source),
            tester.getCenter(destination) - tester.getCenter(source),
          );
        }
        await tester.pumpAndSettle();
      }

      // Cross-kind drops must be rejected.
      await move('menu-project-0', 'drop-tag-태그 폴더');
      expect(projectMoves, isEmpty);
      expect(tagMoves, isEmpty);
      await move('menu-project-0', 'drop-project-프로젝트 폴더');
      expect(projectMoves, ['프로젝트 폴더']);
      await tester.tap(find.text('프로젝트 폴더'));
      await tester.pumpAndSettle();
      await move('menu-project-0', 'drop-project-unfiled');
      expect(projectMoves, ['프로젝트 폴더', null]);
      await move('menu-tag-0', 'drop-tag-태그 폴더');
      expect(tagMoves, ['태그 폴더']);
      await tester.tap(find.text('태그 폴더'));
      await tester.pumpAndSettle();
      await move('menu-tag-0', 'drop-tag-unfiled');
      expect(tagMoves, ['태그 폴더', null]);
      expect(find.text('미분류'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.android,
    }),
  );
}

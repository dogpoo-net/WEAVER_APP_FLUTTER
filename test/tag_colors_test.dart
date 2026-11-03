import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/tag_colors.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(hashtagColors.clear);
  tearDown(hashtagColors.clear);

  test('tag colors survive backups and older backups have no assigned colors', () {
    hashtagColors['생각'] = hashtagPalette[3].toARGB32();
    final saved = WorkspaceSnapshot.encode([]);
    hashtagColors.clear();
    WorkspaceSnapshot.decode(saved).apply();
    expect(hashtagColors['생각'], hashtagPalette[3].toARGB32());
    final legacy = jsonDecode(saved) as Map<String, dynamic>;
    legacy.remove('hashtagColors');
    WorkspaceSnapshot.decode(jsonEncode(legacy)).apply();
    expect(hashtagColors, isEmpty);
  });

  for (final embedded in [false, true]) {
    testWidgets('tag palette selects and cancels without opening tag ($embedded)', (tester) async {
      var changes = 0;
      int? selected;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkspaceMenu(
        embedded: embedded, projects: const [], tags: const ['생각'],
        onSelected: (value) => selected = value,
        onTagColorChanged: () => changes++,
      ))));
      final button = find.byTooltip('#생각 색상 변경');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byKey(const ValueKey('hashtag-palette')));
      expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, 5);
      expect(find.byTooltip(RegExp(r'^색상 \d+$')), findsNWidgets(20));
      await tester.tap(find.byKey(const ValueKey('hashtag-color-7')));
      await tester.pumpAndSettle();
      expect(hashtagColors['생각'], hashtagPalette[7].toARGB32());
      expect(changes, 1);
      expect(selected, isNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(hashtagColors['생각'], hashtagPalette[7].toARGB32());
      expect(tester.takeException(), isNull);
    });
  }
}

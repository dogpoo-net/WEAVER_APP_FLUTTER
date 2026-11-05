import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/tag_colors.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('box and tag color labels edit without changing the active filter', (tester) async {
    elements.clear(); memoBoxes.clear(); hashtagColors.clear();
    final record = elements.add('생각 #독서');
    final box = MemoBox('자료', ids: [record.id]); memoBoxes.add(box);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], onChanged: () => saves++)));
    await tester.tap(find.byTooltip('자료 상자 색상 변경')); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hashtag-palette')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hashtag-color-2'))); await tester.pumpAndSettle();
    expect(box.color, hashtagPalette[2].toARGB32());
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-all'))).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('thought-filter-tag-독서'))); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('#독서 색상 변경')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hashtag-color-5'))); await tester.pumpAndSettle();
    expect(hashtagColors['독서'], hashtagPalette[5].toARGB32());
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-tag-독서'))).selected, isTrue);
    expect(saves, 2);
    final restored = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
    expect(restored.boxes.single.color, hashtagPalette[2].toARGB32());
    expect(restored.tagColors['독서'], hashtagPalette[5].toARGB32());
    expect(tester.takeException(), isNull);
  });
}

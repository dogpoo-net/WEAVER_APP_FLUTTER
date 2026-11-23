import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/tag_colors.dart';
import 'package:weaver/features/inbox/tag_page.dart';

void main() {
  testWidgets('color button updates the tag without opening its detail page', (tester) async {
    var saves = 0;
    addTearDown(hashtagColors.clear);
    await tester.pumpWidget(MaterialApp(home: TagListPage(
      tags: () => ['여행'], notes: const [], onOpen: (_) async {},
      onColorChanged: () => saves++,
    )));
    await tester.tap(find.byTooltip('#여행 색상 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hashtag-color-3')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(hashtagColors['여행'], hashtagPalette[3].toARGB32());
    expect(find.byType(TagPage), findsNothing);
  });
}

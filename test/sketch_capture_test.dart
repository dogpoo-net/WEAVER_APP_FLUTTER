import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:weaver/main.dart';

void main() {
  testWidgets('quick memo attaches a vector sketch after drawing and erasing', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp(requireLogin: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('스케치'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('sketch-canvas'));
    final center = tester.getCenter(canvas);
    await tester.dragFrom(center, const Offset(30, 20));
    await tester.tap(find.byTooltip('지우개'));
    await tester.tapAt(center);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '첨부'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('색상 팔레트'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.circle).last);
    await tester.pumpAndSettle();
    await tester.dragFrom(center, const Offset(60, 30));
    await tester.pump();
    await tester.tap(find.text('첨부'));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.byTooltip('사진 첨부 제거'), findsOneWidget);
  });
}

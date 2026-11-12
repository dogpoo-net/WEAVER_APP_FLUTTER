import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/app_theme.dart';
import 'package:weaver/main.dart';

void main() {
  testWidgets('color sets switch independently and retain the draft', (tester) async {
    await tester.pumpWidget(const MyApp(requireLogin: false, ));
    await tester.enterText(find.byType(TextField).first, '이어 쓰는 생각');
    final originalDark = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

    Future<ColorScheme> choose(String label) async {
      if(find.byKey(const ValueKey('close-settings')).evaluate().isEmpty){if(find.text('환경설정').evaluate().isEmpty){await tester.tap(find.byTooltip('메뉴 열기'));await tester.pumpAndSettle();}await tester.tap(find.text('환경설정').first);await tester.pumpAndSettle();}
      await tester.tap(find.byTooltip('테마 선택'));
      await tester.pumpAndSettle();
      expect(find.byType(PaletteSwatches), findsWidgets);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('이어 쓰는 생각'), findsOneWidget);
      expect(tester.takeException(), isNull);
      return Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
    }

    final neutral = await choose('화이트·그레이');
    expect(neutral.brightness, Brightness.light);
    expect(neutral.surface, const Color(0xFFFAFAFA));
    expect(neutral.primary, const Color(0xFF484848));
    final beige = await choose('베이지');
    expect(beige.brightness, Brightness.light);
    expect(beige.surface, const Color(0xFFF8F4EC));
    final dark = await choose('다크');
    expect(dark, originalDark);
    final light = await choose('라이트');
    expect(light, beige);
  });
}

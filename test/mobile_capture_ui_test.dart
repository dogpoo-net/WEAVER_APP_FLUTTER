import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/capture/geolog_page.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows]) {
    testWidgets('capture controls are mobile only and fit a narrow composer ($platform)', (tester) async {
      tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp()); await tester.pumpAndSettle();
      final expected = platform == TargetPlatform.windows ? findsNothing : findsOneWidget;
      expect(find.byKey(const ValueKey('quick-location')), expected);
      expect(find.byTooltip('음성 메모'), expected);
      expect(find.byTooltip('사진 첨부 (최대 5장)'), expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant({platform}));
  }
  testWidgets('home links to unclassified thoughts and photo menu is anchored to icon', (tester) async {
    await tester.pumpWidget(const MyApp()); await tester.pumpAndSettle();
    final photo = find.byKey(const ValueKey('quick-photo-menu'));
    final button = tester.getRect(photo);
    await tester.tap(photo); await tester.pumpAndSettle();
    final menu = tester.getRect(find.text('사진 선택 (5장까지)'));
    expect((menu.top - button.bottom).abs(), lessThan(80));
    await tester.tapAt(const Offset(5, 5)); await tester.pumpAndSettle();
    final link = find.text('미분류 정리하기');
    await tester.ensureVisible(link); await tester.tap(link); await tester.pumpAndSettle();
    expect(find.byType(ThoughtBoxView), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-box-미분류'))).selected, isTrue);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
  testWidgets('geolog tab opens without requesting location or loading an empty map', (tester) async {
    elements.clear();
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    await tester.tap(find.text('지오로그')); await tester.pumpAndSettle();
    expect(find.byType(GeologPage), findsOneWidget);
    expect(find.textContaining('위치가 기록된 생각이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

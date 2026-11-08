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
      expect(find.byTooltip('녹음 메모'), expected);
      expect(find.byTooltip('사진 첨부 (최대 5장)'), expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant({platform}));
  }
  testWidgets('geolog tab opens without requesting location or loading an empty map', (tester) async {
    elements.clear();
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    await tester.tap(find.text('지오로그')); await tester.pumpAndSettle();
    expect(find.byType(GeologPage), findsOneWidget);
    expect(find.textContaining('위치가 기록된 생각이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

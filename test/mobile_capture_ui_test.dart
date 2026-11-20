import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/capture/geolog_page.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows]) {
    testWidgets('capture controls fit mobile and desktop composers ($platform)', (tester) async {
      tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp(requireLogin: false, )); await tester.pumpAndSettle();
      const expected = findsOneWidget;
      expect(find.byKey(const ValueKey('quick-location')), expected);
      expect(find.byTooltip('음성 메모'), expected);
      expect(find.byTooltip('사진 업로드 (최대 5장)'), expected);
      final location=tester.getRect(find.byKey(const ValueKey('quick-location')));
      final voice=tester.getRect(find.byTooltip('음성 메모'));
      final upload=tester.getRect(find.byKey(const ValueKey('quick-photo-menu')));
      expect(voice.left-location.right,closeTo(4,.1));
      expect(upload.left-voice.right,closeTo(4,.1));
      expect(location.width,voice.width);expect(voice.width,upload.width);
      expect(location.center.dy,closeTo(upload.center.dy,.1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant({platform}));
  }
  testWidgets('home links to unclassified thoughts and photo picker has no dropdown', (tester) async {
    await tester.pumpWidget(const MyApp(requireLogin: false, )); await tester.pumpAndSettle();
    final photo = find.byKey(const ValueKey('quick-photo-menu'));
    await tester.tap(photo); await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>),findsNothing);
    expect(find.text('음성 파일 업로드'),findsNothing);
    final link = find.text('미분류 정리하기');
    await tester.ensureVisible(link); await tester.tap(link); await tester.pumpAndSettle();
    expect(find.byType(ThoughtBoxView), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-box-미분류'))).selected, isTrue);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
  testWidgets('geolog tab opens with a blurred map and top notice without requesting location', (tester) async {
    SharedPreferences.setMockInitialValues({});
    elements.clear();
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(
      notes: [], initialView: ThoughtView.geolog,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(GeologPage), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, 20);
    expect(tester.getTopLeft(find.textContaining('위치가 기록된 생각이 없습니다.')).dy,
      lessThan(tester.getCenter(find.byType(FlutterMap)).dy));
    expect(find.textContaining('위치가 기록된 생각이 없습니다.'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.textContaining('한국 상세 타일'), findsNothing);
    final canvasTab = find.widgetWithText(TextButton, '메모상자');
    await tester.ensureVisible(canvasTab);
    await tester.tap(canvasTab);
    await tester.pumpAndSettle();
    expect(find.byType(GeologPage), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

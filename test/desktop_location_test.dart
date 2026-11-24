import 'package:weaver/features/capture/capture_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/capture/geolog_page.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';

void main(){
 testWidgets('viewer map opens workspace spots without authoring controls', (tester) async {
   final spot = ElementRecord('공유 스팟')
     ..location = ThoughtLocation(35, 127, 1, DateTime.utc(2026));
   ElementRecord? opened;
   await tester.pumpWidget(MaterialApp(home: GeologPage.viewer(
     records: [spot], open: (record) => opened = record)));
   expect(find.byTooltip('위치에 생각 추가'), findsNothing);
   final marker = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single;
   expect(marker.point, const LatLng(35, 127));
   await tester.tap(find.text('공유 스팟'));
   await tester.pump();
   expect(opened, same(spot));
 });
 testWidgets('timeline connects visible locations in recorded order and toggles', (tester) async {
   elements.clear();
   addTearDown(elements.clear);
   for (final day in [3, 1, 2]) {
     elements.add('여행 $day').location = ThoughtLocation(35, 125.0 + day, 1, DateTime.utc(2026, 1, day));
   }
   await tester.pumpWidget(MaterialApp(home: GeologPage(onChanged: () {})));
   final line = find.byType(PolylineLayer);
   expect(tester.widget<PolylineLayer>(line).polylines.single.points.map((p) => p.longitude), [126, 127, 128]);
   await tester.tap(find.byTooltip('타임라인 숨기기'));
   await tester.pump();
   expect(line, findsNothing);
   await tester.tap(find.byTooltip('타임라인 보이기'));
   await tester.pump();
   expect(line, findsOneWidget);
 });
 testWidgets('desktop map confirmation selects location toggle and Enter saves it',(tester)async{
  await tester.pumpWidget(const MyApp(requireLogin:false));await tester.pumpAndSettle();
  final toggle=find.byKey(const ValueKey('quick-location'));
  await tester.tap(toggle);await tester.pumpAndSettle();
  expect(find.byType(FlutterMap),findsOneWidget);
  tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(35,129));await tester.pump();
  await tester.tap(find.text('확인'));await tester.pumpAndSettle();
  expect(tester.widget<IconButton>(toggle).isSelected,isTrue);
  await tester.enterText(find.byKey(const ValueKey('quick-memo')),'지도 위치를 가진 빠른메모');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pumpAndSettle();
  expect(elements.records['지도 위치를 가진 빠른메모']!.location!.latitude,35);
  expect(tester.widget<IconButton>(toggle).isSelected,isFalse);
  await tester.pumpWidget(const SizedBox());
 },variant:TargetPlatformVariant({TargetPlatform.windows}));
 testWidgets('geolog plus creates a located thought and synchronizes once',(tester)async{
  elements.clear();var saved=0;saveWorkspaceContent=()async{saved++;};
  addTearDown(()=>saveWorkspaceContent=null);
  await tester.pumpWidget(MaterialApp(home:GeologPage(onChanged:(){})));
  await tester.tap(find.byTooltip('위치에 생각 추가'));await tester.pump(const Duration(milliseconds:350));
  final maps=tester.widgetList<FlutterMap>(find.byType(FlutterMap));
  maps.last.options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(36,128));await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('geolog-memo-input')),'새 위치 #여행');await tester.pump();
  await tester.tap(find.widgetWithText(TextButton,'저장'));await tester.pumpAndSettle();
  expect(elements.records['새 위치']!.location!.longitude,128);
  expect(elements.records['새 위치']!.tags,contains('여행'));expect(saved,1);
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
}

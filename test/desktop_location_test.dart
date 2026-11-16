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
  await tester.tap(find.widgetWithText(FilledButton,'저장'));await tester.pumpAndSettle();
  expect(elements.records['새 위치']!.location!.longitude,128);
  expect(elements.records['새 위치']!.tags,contains('여행'));expect(saved,1);
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
}

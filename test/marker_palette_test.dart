import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/capture/map_marker_style.dart';
import 'package:weaver/features/capture/location_preview.dart';

void main(){
 test('custom marker colors survive storage without changing location provenance',(){
  final original=ThoughtLocation(37,127,10,DateTime.utc(2026),isCurrentLocation:true);
  expect(markerPalette.length,20);expect(markerPalette.map((c)=>c.value).toSet().length,20);
  for(final color in markerPalette){
   final restored=ThoughtLocation.fromJson(original.withMarkerColor(color.value).toJson())!;
   expect(locationMarkerColor(restored),Color(color.value));
   expect(restored.latitude,original.latitude);expect(restored.recordedAt,original.recordedAt);
   expect(restored.isCurrentLocation,isTrue);
  }
  expect(locationMarkerColor(ThoughtLocation.fromJson(original.toJson())!),currentLocationMarkerColor);
  expect(ThoughtLocation.fromJson({...original.toJson(),'markerColor':'invalid'})!.markerColor,isNull);
 });
 testWidgets('palette previews selected color and cancellation preserves it',(tester)async{
  final original=ThoughtLocation(37,127,0,DateTime.utc(2026));ThoughtLocation? updated;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
   onPressed:()=>showLocationPreview(context,original,onChanged:(value)=>updated=value),child:const Text('열기'))))));
  await tester.tap(find.text('열기'));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('마커 색상'));await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('marker-color-4278222848')));await tester.pumpAndSettle();
  expect(updated!.markerColor,0xFF008000);expect(original.markerColor,isNull);
  final marker=tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.child as Icon;
  expect(marker.color,const Color(0xFF008000));
  await tester.tap(find.byTooltip('마커 색상'));await tester.pumpAndSettle();
  await tester.tap(find.text('취소'));await tester.pumpAndSettle();
  expect(updated!.markerColor,0xFF008000);
  await tester.tap(find.byTooltip('닫기'));await tester.pumpAndSettle();
 });
}

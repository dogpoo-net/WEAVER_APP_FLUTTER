import 'package:weaver/features/capture/location_capture.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:weaver/features/capture/location_editor.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/capture/audio_format.dart';

void main(){
 testWidgets('offline geolog saves GPS coordinates without creating a map', (tester) async {
   locationOfflineStatus = ValueNotifier(true);
   addTearDown(() => locationOfflineStatus = null);
   LocationEntry? result;
   final gps = ThoughtLocation(37, 127, 5, DateTime.now(), isCurrentLocation: true);
   await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
     body: TextButton(onPressed: () async {
       result = await showLocationEditor(context, compose: true, locate: () async => gps);
     }, child: const Text('열기')),
   ))));
   await tester.tap(find.text('열기'));
   await tester.pumpAndSettle();
   expect(find.byType(FlutterMap), findsNothing);
   await tester.enterText(find.byKey(const ValueKey('geolog-memo-input')), '산책');
   await tester.pump();
   await tester.tap(find.text('저장'));
   await tester.pumpAndSettle();
   expect(result?.location, gps);
 });
 testWidgets('manual map selection survives late GPS and saves typed memo',(tester)async{
  final gps=Completer<ThoughtLocation>();LocationEntry? result;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{result=await showLocationEditor(context,compose:true,locate:()=>gps.future);},child:const Text('열기'))))));
  await tester.tap(find.text('열기'));await tester.pump();
  final map=tester.widget<FlutterMap>(find.byType(FlutterMap));
  map.options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(35,129));await tester.pump();
  gps.complete(ThoughtLocation(37,127,10,DateTime.now()));await tester.pumpAndSettle();
  expect(tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point,const LatLng(35,129));
  expect(find.text('지오로그 남기기'),findsOneWidget);
  final input=find.byKey(const ValueKey('geolog-memo-input'));
  expect(tester.widget<TextField>(input).minLines,3);
  expect(tester.getTopLeft(find.widgetWithText(TextButton,'저장')).dy-tester.getBottomLeft(input).dy,lessThan(24));
  expect(find.byTooltip('음성 메모'),findsOneWidget);
  expect(find.byTooltip('사진 업로드 (최대 5장)'),findsOneWidget);
  expect(tester.getCenter(find.byTooltip('마커 색상')).dx,lessThan(tester.getCenter(find.byTooltip('현재 위치')).dx));
  await tester.tap(find.byTooltip('마커 색상'));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('녹색'));await tester.pumpAndSettle();
  map.options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(35,129));await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('geolog-memo-input')),'지도에서 쓴 생각');await tester.pump();
  await tester.tap(find.text('저장'));await tester.pumpAndSettle();
  expect(result!.text,'지도에서 쓴 생각');expect(result!.location.latitude,35);expect(result!.location.markerColor,0xFF008000);
 });
 testWidgets('location failure still permits manual selection without a composer',(tester)async{
  LocationEntry? result;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{result=await showLocationEditor(context,locate:()async=>throw StateError('denied'));},child:const Text('열기'))))));
  await tester.tap(find.text('열기'));await tester.pumpAndSettle();
  expect(find.byType(TextField),findsNothing);
  final save=tester.widget<TextButton>(find.widgetWithText(TextButton,'저장'));expect(save.onPressed,isNull);
  tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(36,128));await tester.pump();
  await tester.tap(find.text('저장'));await tester.pumpAndSettle();
  expect(result!.location.longitude,128);
 });
 testWidgets('detail location is a draft until the thought is saved',(tester)async{
  elements.clear();final record=elements.add('위치 수정');
  record.location=ThoughtLocation(37,127,10,DateTime.now());
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showElementMetadata(context,record.text),child:const Text('상세'))))));
  await tester.tap(find.text('상세'));await tester.pumpAndSettle();
  await tester.ensureVisible(find.byTooltip('위치 기록'));await tester.tap(find.byTooltip('위치 기록'));await tester.pumpAndSettle();
  tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(const TapPosition(Offset.zero,Offset.zero),const LatLng(35,129));await tester.pump();
  await tester.tap(find.widgetWithText(TextButton,'저장').last);await tester.pumpAndSettle();
  expect(record.location!.latitude,37);
  await tester.tap(find.widgetWithText(FilledButton,'저장'));await tester.pumpAndSettle();
  expect(record.location!.latitude,35);
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
 test('uploaded audio formats and long durations preserve compatibility',(){
  expect(audioMime(Uint8List.fromList('ID3audio'.codeUnits)),'audio/mpeg');
  expect(audioMime(Uint8List.fromList([0,0,0,24,...'ftypM4A '.codeUnits])),'audio/mp4');
  expect(()=>audioMime(Uint8List.fromList('bad'.codeUnits)),throwsFormatException);
  expect(VoiceAttachment.fromJson({'id':'upload','durationMs':180000}).durationMs,180000);
  expect(VoiceAttachment.fromJson({'id':'old','durationMs':60000}).durationMs,60000);
  expect(VoiceAttachment.fromJson({'id':'unknown','durationMs':0}).durationMs,0);
 });
}

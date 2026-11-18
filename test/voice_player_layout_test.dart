import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/voice_player.dart';
void main(){
 testWidgets('delete stays in playback row and compact transcript spans full width',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:320,child:VoicePlayer(load:()async=>null,durationMs:1000,transcript:'변환된 본문',trailing:IconButton(key:const ValueKey('delete'),onPressed:(){},icon:const Icon(Icons.delete_outline))))))));
  expect(tester.getCenter(find.byKey(const ValueKey('delete'))).dy,tester.getCenter(find.byTooltip('녹음 재생')).dy);
  final toggle=find.widgetWithText(TextButton,'변환된 텍스트');
  expect(tester.getSize(toggle).height,lessThanOrEqualTo(32));
  await tester.tap(toggle);await tester.pumpAndSettle();
  expect(tester.getSize(find.byType(SelectableText)).width,320);
  final dividers=tester.widgetList<Divider>(find.byType(Divider));
  expect(dividers.length,2);expect(dividers.every((d)=>d.thickness==1),isTrue);
 });
}

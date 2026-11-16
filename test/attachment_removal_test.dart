import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/capture/capture_models.dart';
void main(){
 testWidgets('attachment removals are discarded on close and applied together on save',(tester)async{
  elements.clear();final record=elements.add('첨부 삭제');
  record.location=ThoughtLocation(37,127,0,DateTime.utc(2026));
  record.photos.add(const PhotoAttachment('photo','photo.png'));
  record.recordings.add(const VoiceAttachment('audio',1000));
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showElementMetadata(context,record.text),child:const Text('상세'))))));
  Future<void> remove()async{
   await tester.tap(find.text('상세'));await tester.pump();await tester.pump(const Duration(milliseconds:300));
   for(final label in ['위치 삭제','음성 삭제','사진 삭제']){
    await tester.ensureVisible(find.byTooltip(label));await tester.tap(find.byTooltip(label));await tester.pump();await tester.pump(const Duration(milliseconds:300));
   }
   expect(record.location,isNotNull);expect(record.photos,hasLength(1));expect(record.recordings,hasLength(1));
  }
  await remove();await tester.tap(find.text('닫기'));await tester.pump();await tester.pump(const Duration(milliseconds:300));
  expect(record.location,isNotNull);expect(record.photos,hasLength(1));expect(record.recordings,hasLength(1));
  await remove();await tester.tap(find.widgetWithText(FilledButton,'저장'));await tester.pump();await tester.pump(const Duration(milliseconds:300));
  expect(find.text('삭제된 데이터가 있습니다. 저장하시겠습니까?'),findsOneWidget);
  await tester.tap(find.text('취소'));await tester.pumpAndSettle();
  expect(record.location,isNotNull);expect(record.photos,hasLength(1));expect(record.recordings,hasLength(1));
  await tester.tap(find.widgetWithText(FilledButton,'저장'));await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton,'저장').last);await tester.pumpAndSettle();
  expect(record.location,isNull);expect(record.photos,isEmpty);expect(record.recordings,isEmpty);expect(elements.trash,isEmpty);
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
}

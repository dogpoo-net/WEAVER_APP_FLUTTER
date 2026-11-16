import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_comments.dart';
void main(){
 for(final scale in [1.0,1.5]){
 testWidgets('attachment icons align with first line at scale $scale',(tester)async{
  elements.clear();memoCommentCounts.value={};final record=elements.add('첫 줄\n둘째 줄');
  record.location=ThoughtLocation(37,127,0,DateTime.utc(2026));
  record.recordings.add(const VoiceAttachment('voice',1000));
  record.photos.add(const PhotoAttachment('photo','photo.png'));
  await tester.pumpWidget(MaterialApp(home:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(scale)),child:Scaffold(body:WordBadge(word:record.text,fullText:true,onTap:(){})))));
  final label=tester.getRect(find.text(record.text));
  final location=tester.getRect(find.byIcon(Icons.location_on_outlined));
  final voice=tester.getRect(find.byIcon(Icons.mic_none));
  final photo=tester.getRect(find.byIcon(Icons.image_outlined));
  expect(location.center.dy,closeTo(label.top+label.height/4,.5));
  expect(voice.center.dy,closeTo(location.center.dy,.1));expect(photo.center.dy,closeTo(location.center.dy,.1));
  expect(location.left,lessThan(voice.left));expect(voice.left,lessThan(photo.left));
  await tester.pumpWidget(const SizedBox());elements.clear();
 });
 }

 testWidgets('comment counter has equal top and right inset',(tester)async{
  elements.clear();final record=elements.add('메모\n둘째 줄');memoCommentCounts.value={record.id:3};
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:WordBadge(word:record.text,fullText:true,onTap:(){})))));
  final count=find.byKey(ValueKey('comment-count-${record.id}'));
  final pill=tester.getRect(find.ancestor(of:count,matching:find.byType(Container)).first);
  final badge=tester.getRect(find.byType(TextButton));
  expect(pill.top-badge.top,closeTo(badge.right-pill.right,.1));
  expect(pill.top-badge.top,closeTo(6,.1));
  await tester.pumpWidget(const SizedBox());memoCommentCounts.value={};elements.clear();
 });

 testWidgets('square thoughts center vertically and align left',(tester)async{
  elements.clear();memoCommentCounts.value={};elements.add('한 줄');
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:180,height:180,child:WordBadge(word:'한 줄',fullText:true,square:true,onTap:(){}))))));
  final label=tester.getRect(find.text('한 줄')),button=tester.getRect(find.byType(TextButton));
  expect(label.center.dy,closeTo(button.center.dy,.1));expect(label.left-button.left,closeTo(4,.1));
 });
 testWidgets('home and thought row badges share tight padding',(tester)async{
  elements.clear();memoCommentCounts.value={};elements.add('같은 메모');
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   WordBadge(word:'같은 메모',fullText:true,onTap:(){}),
   WordBadge(word:'같은 메모',fullText:true,compact:true,onTap:(){}),
  ]))));
  final buttons=find.byType(TextButton),texts=find.text('같은 메모');
  expect(tester.getSize(buttons.first),tester.getSize(buttons.last));
  final button=tester.getRect(buttons.first),text=tester.getRect(texts.first);
  expect(button.bottom-text.bottom,closeTo(4,.1));expect(button.right-text.right,closeTo(4,.1));
 });
}

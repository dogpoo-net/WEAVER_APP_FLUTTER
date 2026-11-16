import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_comments.dart';
void main(){
 tearDown((){memoCommentRequest=null;memoCommentsWritable=false;memoCommentCounts.value={};});
 testWidgets('badge counts appear only for comments and update in place',(tester)async{
 elements.clear();final memo=elements.add('댓글 메모\n두 번째 줄\n세 번째 줄');
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:WordBadge(word:memo.text,fullText:true,onTap:(){}))));
 final count=find.byKey(ValueKey('comment-count-${memo.id}'));
 expect(count,findsNothing);
 memoCommentCounts.value={memo.id:12};await tester.pump();
 expect(count,findsOneWidget);expect(find.text('12'),findsOneWidget);
 expect(tester.getCenter(count).dy,closeTo(tester.getCenter(find.text(memo.text)).dy,.1));
 expect(tester.getCenter(count).dx,lessThan(tester.getCenter(find.text(memo.text)).dx));
 memoCommentCounts.value={};await tester.pump();expect(count,findsNothing);
 await tester.pumpWidget(const SizedBox());elements.clear();
 });
 test('relative comment dates cover seconds through years',(){final now=DateTime.utc(2026,11,16);for(final e in {5:'5초 전',120:'2분 전',7200:'2시간 전',172800:'2일 전',2592000:'1개월 전',31536000:'1년 전',63072000:'2년 전'}.entries){expect(commentAge(now.subtract(Duration(seconds:e.key)),now),e.value);}expect(commentAge(now.add(const Duration(seconds:5)),now),'0초 전');});
 testWidgets('comments load author and time and submit separately from memo content',(tester)async{
  var writes=0;memoCommentsWritable=true;memoCommentRequest=(action,body)async{expect(body['memoId'],'memo');if(action.endsWith('write')){writes++;expect(body['content'],'새 댓글');expect(body['requestId'],isNotEmpty);}return {'commentCount':writes+1,'comments':[{'id':1,'content':writes==0?'기존 댓글':'새 댓글','author':'작성자','createdAt':DateTime.now().toUtc().subtract(const Duration(minutes:2)).toIso8601String()}]};};
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showMemoComments(context,'memo',write:true),child:const Text('열기'))))));await tester.tap(find.text('열기'));await tester.pumpAndSettle();
  expect(find.text('작성자'),findsOneWidget);expect(find.text('2분 전'),findsOneWidget);expect(find.text('기존 댓글'),findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('memo-comment-input')),'새 댓글');await tester.tap(find.text('댓글 등록'));await tester.pumpAndSettle();expect(writes,1);expect(memoCommentCounts.value['memo'],2);expect(find.text('새 댓글'),findsOneWidget);
  await tester.tap(find.text('닫기'));await tester.pumpAndSettle();
 });
}

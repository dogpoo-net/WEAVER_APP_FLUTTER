import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/memo_comments.dart';
void main(){
 tearDown((){memoCommentRequest=null;memoCommentsWritable=false;});
 test('relative comment dates cover seconds through years',(){final now=DateTime.utc(2026,11,16);for(final e in {5:'5초 전',120:'2분 전',7200:'2시간 전',172800:'2일 전',2592000:'1개월 전',31536000:'1년 전',63072000:'2년 전'}.entries){expect(commentAge(now.subtract(Duration(seconds:e.key)),now),e.value);}expect(commentAge(now.add(const Duration(seconds:5)),now),'0초 전');});
 testWidgets('comments load author and time and submit separately from memo content',(tester)async{
  var writes=0;memoCommentsWritable=true;memoCommentRequest=(action,body)async{expect(body['memoId'],'memo');if(action.endsWith('write')){writes++;expect(body['content'],'새 댓글');expect(body['requestId'],isNotEmpty);}return {'comments':[{'id':1,'content':writes==0?'기존 댓글':'새 댓글','author':'작성자','createdAt':DateTime.now().toUtc().subtract(const Duration(minutes:2)).toIso8601String()}]};};
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showMemoComments(context,'memo',write:true),child:const Text('열기'))))));await tester.tap(find.text('열기'));await tester.pumpAndSettle();
  expect(find.text('작성자'),findsOneWidget);expect(find.text('2분 전'),findsOneWidget);expect(find.text('기존 댓글'),findsOneWidget);
  await tester.enterText(find.byKey(const ValueKey('memo-comment-input')),'새 댓글');await tester.tap(find.text('댓글 등록'));await tester.pumpAndSettle();expect(writes,1);expect(find.text('새 댓글'),findsOneWidget);
  await tester.tap(find.text('닫기'));await tester.pumpAndSettle();
 });
}

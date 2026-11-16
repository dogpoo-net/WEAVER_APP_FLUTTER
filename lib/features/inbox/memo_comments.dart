import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'workspace_routes.dart';

typedef CommentRequest = Future<Map<String,dynamic>> Function(String, Map<String,Object?>);
CommentRequest? memoCommentRequest;
bool memoCommentsWritable = false;
String commentAge(DateTime date, DateTime now) {
  final seconds=max(0,now.difference(date).inSeconds);
  if(seconds<60)return '$seconds초 전';
  if(seconds<3600)return '${seconds~/60}분 전';
  if(seconds<86400)return '${seconds~/3600}시간 전';
  final days=seconds~/86400;
  if(days<30)return '$days일 전';
  if(days<365)return '${days~/30}개월 전';
  return '${days~/365}년 전';
}
Future<void> showMemoComments(BuildContext context,String memoId,{bool write=false}) async {
  final request=memoCommentRequest;
  if(request==null){await showDialog<void>(context:context,builder:(context)=>AlertDialog(content:const Text('댓글은 로그인 후 서버에 저장된 메모에서 사용할 수 있습니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('닫기'))]));return;}
  await showDialog<void>(context:context,builder:(_)=>_Comments(memoId:memoId,request:request,write:write,canWrite:memoCommentsWritable));
}
class _Comments extends StatefulWidget {
 const _Comments({required this.memoId,required this.request,required this.write,required this.canWrite});
 final String memoId;final CommentRequest request;final bool write,canWrite;
 @override State<_Comments> createState()=>_CommentsState();
}
class _CommentsState extends State<_Comments> {
 final text=TextEditingController();final focus=FocusNode();
 List<Map<String,dynamic>> items=[];bool loading=false,sending=false,more=false;String? error,requestId,submittedText;Timer? clock;
 @override void initState(){super.initState();load();clock=Timer.periodic(const Duration(seconds:30),(_){if(mounted)setState((){});});}
 @override void dispose(){clock?.cancel();text.dispose();focus.dispose();super.dispose();}
 Future<void> load({bool older=false})async{
  if(loading)return;setState((){loading=true;error=null;});
  try{final r=await widget.request('comments/read',{'memoId':widget.memoId,if(older&&items.isNotEmpty)'beforeId':items.last['id']});if(!mounted)return;
   final rows=(r['comments'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();setState((){items=older?[...items,...rows]:rows;more=rows.length==50;});
  }catch(e){if(mounted)setState(()=>error='$e');}finally{if(mounted)setState(()=>loading=false);}
 }
 Future<void> send()async{
  final content=text.text.trim();if(sending||content.isEmpty)return;
  if(content.runes.length>4000){setState(()=>error='댓글은 4000자 이하로 입력해주세요.');return;}
  if(requestId==null||submittedText!=content){final r=Random.secure();final h=List.generate(32,(_)=>r.nextInt(16).toRadixString(16)).join();requestId='${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';submittedText=content;}
  setState((){sending=true;error=null;});
  try{await saveWorkspaceContent?.call();final r=await widget.request('comments/write',{'memoId':widget.memoId,'content':content,'requestId':requestId});if(!mounted)return;
   setState((){items=(r['comments'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();more=items.length==50;text.clear();requestId=null;submittedText=null;});
  }catch(e){if(mounted)setState(()=>error='$e');}finally{if(mounted)setState(()=>sending=false);}
 }
 @override Widget build(BuildContext context)=>AlertDialog(
  title:Row(children:[const Expanded(child:Text('댓글')),IconButton(tooltip:'댓글 새로고침',onPressed:loading||sending?null:()=>load(),icon:const Icon(Icons.refresh))]),
  content:SizedBox(width:480,height:MediaQuery.sizeOf(context).height*.55,child:Column(children:[
   if(loading)const LinearProgressIndicator(),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   Expanded(child:items.isEmpty?const Center(child:Text('아직 댓글이 없습니다.')):ListView.builder(itemCount:items.length+(more?1:0),itemBuilder:(context,i){
    if(i==items.length)return TextButton(onPressed:loading?null:()=>load(older:true),child:const Text('이전 댓글 더보기'));
    final row=items[i];final date=DateTime.tryParse(row['createdAt'] as String? ?? '');
    return Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[Expanded(child:Text(row['author'] as String? ?? '이름 없음',style:Theme.of(context).textTheme.labelLarge)),if(date!=null)Tooltip(message:date.toLocal().toString().split('.').first,child:Text(commentAge(date,DateTime.now()),style:Theme.of(context).textTheme.bodySmall))]),
     const SizedBox(height:4),SelectableText(row['content'] as String? ?? ''),const Divider(),
    ]));
   })),
   if(!widget.canWrite)const Text('읽기 전용 워크스페이스에서는 댓글을 작성할 수 없습니다.'),
   if(widget.canWrite)TextField(key:const ValueKey('memo-comment-input'),controller:text,focusNode:focus,autofocus:widget.write,enabled:!sending,minLines:2,maxLines:4,maxLength:4000,decoration:const InputDecoration(hintText:'댓글을 입력하세요.')),
  ])),
  actions:[if(widget.canWrite)FilledButton(onPressed:sending?null:send,child:Text(sending?'등록 중…':'댓글 등록')),TextButton(onPressed:sending?null:()=>Navigator.pop(context),child:const Text('닫기'))]);
}

import 'package:flutter/material.dart';
import 'workspace_deletion_dialog.dart';

class AdminBackofficePage extends StatefulWidget {
  const AdminBackofficePage({super.key,required this.request});
  final WorkspaceRequest request;
  @override State<AdminBackofficePage> createState()=>_AdminBackofficePageState();
}
class _AdminBackofficePageState extends State<AdminBackofficePage>{
  final search=TextEditingController();List<dynamic> users=[],spaces=[],audit=[];Map? account;
  bool busy=false;String? error;
  @override void initState(){super.initState();run(find);}
  @override void dispose(){search.dispose();super.dispose();}
  Future<void> run(Future<void> Function() action)async{if(busy)return;setState((){busy=true;error=null;});try{await action();}catch(e){if(mounted)setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> find()async{final result=await widget.request('admin/users',{'query':search.text.trim()});if(mounted)setState(()=>users=result['users'] as List);}
  Future<void> select(String id)async{final result=await widget.request('admin/account',{'userId':id});if(mounted)setState((){account=result['account'] as Map;spaces=result['workspaces'] as List;});}
  Future<bool> confirm(String text)async=>await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('관리자 변경 확인'),content:Text(text),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('변경'))]))==true;
  Future<void> subscription(Map row)async{
    final result=await showDialog<Map<String,Object?>>(context:context,builder:(_)=>_SubscriptionEdit(row:row));
    if(result==null)return;await widget.request('admin/subscription',{'workspaceId':row['workspaceId'],...result});await select(account!['id']);
  }
  Future<void> members(Map row)async{
    final response=await widget.request('admin/members',{'workspaceId':row['workspaceId']});if(!mounted)return;
    await showDialog<void>(context:context,builder:(_)=>_AdminMembers(request:widget.request,id:row['workspaceId'],members:response['members'] as List));
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!busy,child:Scaffold(
    appBar:AppBar(automaticallyImplyLeading:false,title:const Text('관리자 백오피스'),actions:[TextButton.icon(onPressed:busy?null:()=>Navigator.pop(context),icon:const Icon(Icons.logout),label:const Text('나가기'))]),
    body:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1000),child:ListView(padding:const EdgeInsets.all(16),children:[
      if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      TextField(controller:search,enabled:!busy,decoration:InputDecoration(labelText:'계정 이메일 검색',suffixIcon:IconButton(onPressed:busy?null:()=>run(find),icon:const Icon(Icons.search))),onSubmitted:(_)=>run(find)),
      for(final user in users)ListTile(dense:true,title:Text(user['name']??user['email']),subtitle:Text(user['email']),trailing:Text(user['platformRole']=='admin'?'관리자':'일반'),selected:user['id']==account?['id'],onTap:busy?null:()=>run(()=>select(user['id']))),
      if(account!=null)...[const Divider(),Text('${account!['name']??''} · ${account!['email']}',style:Theme.of(context).textTheme.titleMedium),
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('계정 권한'),trailing:DropdownButton<String>(value:account!['platformRole'],items:const[DropdownMenuItem(value:'user',child:Text('일반 사용자')),DropdownMenuItem(value:'admin',child:Text('관리자'))],onChanged:busy?null:(role)=>run(()async{if(role==null||role==account!['platformRole']||!await confirm('이 계정의 권한을 ${role=='admin'?'관리자':'일반 사용자'}로 변경할까요?'))return;await widget.request('admin/account-role',{'userId':account!['id'],'role':role});await select(account!['id']);await find();}))),
        const Text('구독은 워크스페이스별로 적용됩니다. 변경할 공간을 선택하세요.'),
        if(spaces.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('소유한 워크스페이스가 없습니다.')),
        for(final row in spaces)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(row['name']??'워크스페이스',style:Theme.of(context).textTheme.titleMedium),Text('${row['plan']} · ${row['archivedAt']==null?'활성':'삭제 보관 중'}'),if((row['subscription'] as Map)['periodEnd']!=null)Text('종료: ${(row['subscription'] as Map)['periodEnd']}'),Wrap(spacing:8,children:[TextButton(onPressed:busy?null:()=>run(()=>subscription(row)),child:const Text('플랜·구독 상태 변경')),TextButton(onPressed:busy?null:()=>run(()=>members(row)),child:const Text('멤버 권한 관리'))])]))),
      ],
      const Divider(),TextButton(onPressed:busy?null:()=>run(()async{final result=await widget.request('admin/audit',{});if(mounted)setState(()=>audit=result['events'] as List);}),child:const Text('최근 관리자·정책 변경 이력')),
      for(final row in audit)ListTile(dense:true,title:Text('${row['action']} · ${row['targetId']}'),subtitle:Text('${row['createdAt']} · ${row['actorId']??'탈퇴 계정'}\n${row['details']}')),
    ]))),
  ));
}
class _SubscriptionEdit extends StatefulWidget{
 const _SubscriptionEdit({required this.row});final Map row;
 @override State<_SubscriptionEdit> createState()=>_SubscriptionEditState();
}
class _SubscriptionEditState extends State<_SubscriptionEdit>{
 late String plan=widget.row['plan']??'free';late final end=TextEditingController(text:(widget.row['subscription'] as Map)['periodEnd']??'');
 late bool cancel=(widget.row['subscription'] as Map)['cancelAtEnd']==true||(widget.row['subscription'] as Map)['cancelAtEnd']==1;
 String? error;
 @override void dispose(){end.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>AlertDialog(title:const Text('구독 상태 변경'),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
  DropdownButtonFormField<String>(initialValue:plan,decoration:const InputDecoration(labelText:'플랜'),items:const[DropdownMenuItem(value:'free',child:Text('Free')),DropdownMenuItem(value:'standard',child:Text('Standard')),DropdownMenuItem(value:'pro',child:Text('Pro'))],onChanged:(v)=>setState(()=>plan=v!)),
  if(plan!='free')...[TextField(controller:end,decoration:const InputDecoration(labelText:'종료일 (시간대 포함)',hintText:'2026-12-31T23:59:59+09:00')),CheckboxListTile(contentPadding:EdgeInsets.zero,value:cancel,onChanged:(v)=>setState(()=>cancel=v!),title:const Text('기간 종료 시 취소 예약'))],
  const Text('Free 변경은 즉시 적용됩니다. 기존 자료는 삭제하지 않습니다. 실제 결제·환불은 수행하지 않습니다.'),if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
 ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소')),TextButton(onPressed:(){final value=DateTime.tryParse(end.text.trim());if(plan!='free'&&(value==null||!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(end.text.trim())||!value.isAfter(DateTime.now()))){setState(()=>error='시간대가 포함된 미래 종료일을 입력해주세요.');return;}Navigator.pop(context,{'plan':plan,'periodEnd':value?.toUtc().toIso8601String(),'cancel':cancel});},child:const Text('적용'))]);
}
class _AdminMembers extends StatefulWidget{
 const _AdminMembers({required this.request,required this.id,required this.members});final WorkspaceRequest request;final String id;final List<dynamic> members;
 @override State<_AdminMembers> createState()=>_AdminMembersState();
}
class _AdminMembersState extends State<_AdminMembers>{bool busy=false;String? error;late List<dynamic> members=widget.members;
 @override Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(title:const Text('멤버 권한 관리'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!),if(members.isEmpty)const Text('소유자 외 참여자가 없습니다.'),for(final row in members)ListTile(contentPadding:EdgeInsets.zero,title:Text(row['name']??row['email']),subtitle:Text(row['email']),trailing:DropdownButton<String>(value:row['role'],items:const[DropdownMenuItem(value:'editor',child:Text('편집자')),DropdownMenuItem(value:'viewer',child:Text('읽기 전용'))],onChanged:busy?null:(role)async{if(role==null||role==row['role'])return;setState((){busy=true;error=null;});try{await widget.request('admin/member-role',{'workspaceId':widget.id,'userId':row['userId'],'role':role});final result=await widget.request('admin/members',{'workspaceId':widget.id});if(mounted)setState(()=>members=result['members'] as List);}catch(e){if(mounted)setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}}))]))),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('닫기'))]));}

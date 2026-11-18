import 'package:flutter/material.dart';
import 'workspace_deletion_dialog.dart';
import 'subscription_date.dart';

class WorkspacePolicyPage extends StatefulWidget {
  const WorkspacePolicyPage({super.key,required this.request,required this.workspaceId,required this.owner});
  final WorkspaceRequest request;final String workspaceId;final bool owner;
  @override State<WorkspacePolicyPage> createState()=>_WorkspacePolicyPageState();
}
class _WorkspacePolicyPageState extends State<WorkspacePolicyPage>{
  Map<String,dynamic>? data;List<dynamic> spaces=[],members=[];Set<String> selected={},editors={};bool busy=false;String? error;
  @override void initState(){super.initState();load();}
  Future<void> run(Future<void> Function() action)async{if(busy)return;setState((){busy=true;error=null;});try{await action();}catch(e){if(mounted)setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> load()=>run(refresh);
  Future<void> refresh()async{
    final status=await widget.request('subscription',{'workspaceId':widget.workspaceId});
    final catalog=await widget.request('catalog',{});
    final people=widget.owner?await widget.request('members',{'workspaceId':widget.workspaceId}):<String,dynamic>{'members':[]};
    if(!mounted)return;
    setState((){data=status;spaces=(catalog['workspaces'] as List).where((r)=>r['role']=='owner').toList();members=(people['members'] as List).where((r)=>r['role']!='owner').toList();selected=spaces.where((r)=>r['quotaReadOnly']!=true).map((r)=>r['workspaceId'] as String).toSet();editors=members.where((r)=>r['role']=='editor').map((r)=>r['userId'] as String).toSet();});
  }
  @override Widget build(BuildContext context){
    final subscription=data?['subscription'] as Map? ?? {};final plan=data?['plan'] as Map? ?? {};
    final paid=plan['code']!=null&&plan['code']!='free';final cancelled=subscription['cancelAtEnd']==true||subscription['cancelAtEnd']==1;
    return Scaffold(appBar:AppBar(title:const Text('구독 관리')),body:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:ListView(padding:const EdgeInsets.all(16),children:[
      if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      Text('${plan['code']??'…'}',style:Theme.of(context).textTheme.titleLarge),
      if(subscription['periodEnd']!=null)Text('이용 기간 종료: ${subscriptionEndDate(subscription['periodEnd'] as String)} 23:59:59 (한국 시간)'),
      if(paid)Text(cancelled?'구독 취소 예약됨 · 종료일까지 유료 기능 유지':'유료 이용 기간 중'),
      Text('저장 용량: ${data?['bytes']??0} bytes / ${plan['storage_limit']??'플랜 한도 미정'}'),
      Text('문서 수: ${data?['documents']??0} / ${plan['document_limit']??'한도 미정'}'),
      const Text('구독은 소유자의 모든 공간에 적용됩니다. Free 2개(오프라인), Standard 10개, Pro 무제한입니다. 실제 결제는 아직 연결되지 않았습니다. 이용 기간이 끝나면 Free로 전환되며 기존 자료는 삭제하지 않습니다.'),
      if(widget.owner&&paid)TextButton(onPressed:busy?null:()=>run(()async{
        final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:Text(cancelled?'취소 예약을 해제할까요?':'기간 종료 시 구독을 취소할까요?'),content:const Text('현재 이용 기간까지 권한을 유지합니다. 실제 결제 연동 전에는 자동 연장이나 청구가 발생하지 않습니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('닫기')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('확인'))]));
        if(yes!=true)return;await widget.request('subscription-cancel',{'workspaceId':widget.workspaceId,'cancel':!cancelled});await refresh();
      }),child:Text(cancelled?'구독 취소 예약 해제':'구독 취소 예약')),
      if(spaces.isNotEmpty)...[const Divider(),const Text('사용할 소유 워크스페이스 선택'),const Text('한도 초과 시 선택된 공간을 우선 사용합니다. 다른 공간은 조회·정리할 수 있습니다.'),
        for(final row in spaces)CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text(row['name']??'워크스페이스'),value:selected.contains(row['workspaceId']),onChanged:busy?null:(value)=>setState((){if(value==true){selected.add(row['workspaceId']);}else{selected.remove(row['workspaceId']);}})),
        TextButton(onPressed:busy?null:()=>run(()async{await widget.request('select-active-workspaces',{'ids':selected.toList()});await refresh();}),child:const Text('사용할 공간 저장'))],
      if(widget.owner&&members.isNotEmpty)...[const Divider(),const Text('편집자로 유지할 참여자 선택'),
        for(final row in members)CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text(row['name']??row['email']),subtitle:Text(row['email']),value:editors.contains(row['userId']),onChanged:busy?null:(v)=>setState((){if(v==true){editors.add(row['userId']);}else{editors.remove(row['userId']);}})),
        TextButton(onPressed:busy?null:()=>run(()async{await widget.request('select-editors',{'workspaceId':widget.workspaceId,'ids':editors.toList()});await refresh();}),child:const Text('편집자 선택 저장'))],
    ]))));
  }
}

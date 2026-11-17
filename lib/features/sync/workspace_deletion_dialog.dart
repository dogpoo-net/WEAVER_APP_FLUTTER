import 'package:flutter/material.dart';

typedef WorkspaceRequest = Future<Map<String,dynamic>> Function(String,Map<String,Object?>);
class WorkspaceDeletionDialog extends StatefulWidget {
  const WorkspaceDeletionDialog({super.key,required this.id,required this.request});
  final String id;
  final WorkspaceRequest request;
  @override State<WorkspaceDeletionDialog> createState()=>_WorkspaceDeletionDialogState();
}
class _WorkspaceDeletionDialogState extends State<WorkspaceDeletionDialog>{
  final code=TextEditingController();
  bool busy=true, requiresEmail=true, sent=false;
  int retentionDays=0;
  String? error;
  @override void initState(){super.initState();preview();}
  @override void dispose(){code.dispose();super.dispose();}
  Future<void> preview()async{
    try{final result=await widget.request('delete-workspace-preview',{'workspaceId':widget.id});
      if(mounted)setState((){requiresEmail=result['requiresEmail']==true;retentionDays=(result['retentionDays'] as num?)?.toInt()??30;});
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> send()async{
    setState((){busy=true;error=null;});
    try{await widget.request('delete-workspace-email',{'workspaceId':widget.id});if(mounted)setState(()=>sent=true);}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> remove()async{
    if(busy)return;setState((){busy=true;error=null;});
    try{await widget.request('delete-workspace',{'workspaceId':widget.id,if(requiresEmail)'code':code.text.trim()});
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted){setState(()=>error=e.toString());await preview();}}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:const Text('워크스페이스 삭제'),
    content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(requiresEmail&&retentionDays==0?'소유자의 이메일 인증 후 즉시 영구 삭제됩니다. 참여자 모두의 문서·메모·첨부파일이 삭제되며 복원할 수 없습니다.':requiresEmail?'소유자의 이메일 인증이 필요합니다. 삭제 후 30일간 보관되며, 그동안 유료 구독 중인 소유자가 복원할 수 있습니다. 30일 후 자료와 첨부파일은 영구 삭제됩니다.':'이메일 인증 없이 삭제할 수 있습니다. 삭제 후 30일간 보관되며, 유료 구독 중인 소유자가 복원할 수 있습니다. 이 기기에만 있는 오프라인 자료는 별도 파일로 보관해주세요.'),
      if(requiresEmail)...[
        TextButton(onPressed:busy?null:send,child:Text(sent?'인증메일 다시 보내기':'소유자 이메일로 인증메일 보내기')),
        if(sent)const Text('소유자 이메일로 인증코드를 보냈습니다. 10분 안에 입력해주세요.'),
        TextField(controller:code,enabled:!busy,keyboardType:TextInputType.number,maxLength:8,
          decoration:const InputDecoration(labelText:'이메일 인증코드'),onChanged:(_)=>setState((){})),
      ],
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(busy)const LinearProgressIndicator(),
    ]))),
    actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context,false),child:const Text('취소')),
      TextButton(onPressed:busy||(requiresEmail&&(!sent||code.text.trim().length!=8))?null:remove,
        child:Text(requiresEmail?'인증 후 삭제':'삭제'))],
  ));
}

class DeletedWorkspacesDialog extends StatefulWidget {
  const DeletedWorkspacesDialog({super.key,required this.request,required this.onRestored});
  final WorkspaceRequest request;
  final Future<void> Function() onRestored;
  @override State<DeletedWorkspacesDialog> createState()=>_DeletedWorkspacesDialogState();
}
class _DeletedWorkspacesDialogState extends State<DeletedWorkspacesDialog>{
  List<dynamic> rows=[];bool busy=true;String? error;
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    try{final result=await widget.request('deleted-workspaces',{});if(mounted)setState(()=>rows=result['workspaces'] as List);}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> restore(String id)async{
    setState((){busy=true;error=null;});
    try{await widget.request('restore-workspace',{'workspaceId':id});await widget.onRestored();await load();}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:const Text('삭제된 워크스페이스'),
    content:SizedBox(width:480,child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height*.6),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('사용한 공간은 모든 플랜에서 30일 보관합니다. 보관 기한 안에 유료 구독으로 전환하면 복원할 수 있습니다.'),
      if(busy)const LinearProgressIndicator(),
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(!busy&&rows.isEmpty)const Text('복원할 워크스페이스가 없습니다.'),
      for(final row in rows)ListTile(title:Text(row['name']),subtitle:Text('영구 삭제 예정: ${DateTime.parse(row['purgeAfter']).toLocal().toString().substring(0,16)}'),
        trailing:TextButton(onPressed:busy||row['canRestore']==false?null:()=>restore(row['workspaceId']),child:Text(row['canRestore']==false?'유료 구독 필요':'복원'))),
    ])))),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('닫기'))],
  ));
}

import 'package:flutter/material.dart';
import 'workspace_deletion_dialog.dart';
import 'sharing_pages.dart' show roleLabel;

class WorkspacePicker extends StatefulWidget {
  const WorkspacePicker({super.key,required this.workspaces,required this.selected,required this.request,required this.onCatalog,this.onManageMembers});
  final Future<void> Function(Map)? onManageMembers;
  final List<dynamic> workspaces;
  final String? selected;
  final Future<Map<String,dynamic>> Function(String,Map<String,Object?>) request;
  final void Function(List<dynamic>) onCatalog;
  @override
  State<WorkspacePicker> createState()=>_WorkspacePickerState();
}
class _WorkspacePickerState extends State<WorkspacePicker>{
  late List<dynamic> rows=List.of(widget.workspaces);
  bool busy=false;
  String? error;
  Future<String?> nameDialog({String? initial})async{
    final controller=TextEditingController(text:initial??'');
    try{return await showDialog<String>(context:context,builder:(context)=>AlertDialog(
      title:Text(initial==null?'워크스페이스 추가':'이름 변경'),
      content:SizedBox(width:360,child:TextField(controller:controller,autofocus:true,maxLength:80,
        decoration:const InputDecoration(labelText:'워크스페이스 이름'),
        onSubmitted:(value){if(value.trim().isNotEmpty)Navigator.pop(context,value.trim());})),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소')),
        TextButton(onPressed:(){if(controller.text.trim().isNotEmpty)Navigator.pop(context,controller.text.trim());},child:const Text('저장'))],
    ));}finally{ // Let the closing route finish using its controller.
      Future<void>.delayed(const Duration(milliseconds:400),controller.dispose);
    }
  }
  Future<void> change(String action,[Map? row])async{
    if(busy)return;
    String? name;
    if(action=='delete-workspace'){
      final deleted=await showDialog<bool>(context:context,builder:(_)=>WorkspaceDeletionDialog(id:row!['workspaceId'],request:widget.request));
      if(deleted!=true||!mounted)return;
    }else if(action=='create-workspace'||action=='rename-workspace'){
      name=await nameDialog(initial:row==null?null:(row['name']??'내 워크스페이스'));
      if(name==null||!mounted)return;
    }else{
      final deleting=action=='delete-workspace';
      final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
        title:Text(deleting?'워크스페이스를 삭제할까요?':'워크스페이스에서 나갈까요?'),
        content:Text(deleting?'참여자 모두의 문서·메모·첨부파일이 삭제되며 되돌릴 수 없습니다.':'이 공간에 접근할 수 없게 됩니다. 작성한 자료와 작성자 이름은 그대로 남습니다.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),
          TextButton(onPressed:()=>Navigator.pop(context,true),child:Text(deleting?'삭제':'나가기'))],
      ));
      if(yes!=true||!mounted)return;
    }
    setState((){busy=true;error=null;});
    try{
      final result=action=='delete-workspace'?<String,dynamic>{}:await widget.request(action,{if(row!=null)'workspaceId':row['workspaceId'],'name':?name});
      final catalog=await widget.request('catalog',{});
      if(!mounted)return;
      setState(()=>rows=catalog['workspaces'] as List);
      widget.onCatalog(rows);
      if(action=='create-workspace'){
        Navigator.pop(context,result['workspaceId']);
      }else if((action=='delete-workspace'||action=='leave-workspace')&&row?['workspaceId']==widget.selected){
        Navigator.pop(context,catalog['defaultWorkspaceId']);
      }
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget entry(Map row)=>ListTile(
    contentPadding: const EdgeInsets.only(left: 4),
    minLeadingWidth: 18, horizontalTitleGap: 8,
    minVerticalPadding: 4,
    visualDensity: const VisualDensity(vertical: -2),
    title:Text.rich(TextSpan(children:[
      TextSpan(text:row['name']??'내 워크스페이스'),
      if(row['role']!='owner' && (row['ownerName'] as String? ?? '').isNotEmpty)
        TextSpan(text:'  ${row['ownerName']}',style:Theme.of(context).textTheme.bodySmall?.copyWith(
          color:Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha:.8))),
    ])),subtitle:Text(roleLabel(row['role'])),
    leading:row['workspaceId']==widget.selected?const Icon(Icons.check, size:18):const SizedBox(width:18),
    onTap:busy?null:()=>Navigator.pop(context,row['workspaceId']),
    trailing:PopupMenuButton<String>(tooltip:'워크스페이스 관리',enabled:!busy,
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 40), maximumSize: const Size(36, 40),
        padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelected:(action)async{
        if(action=='members'){Navigator.pop(context);await widget.onManageMembers?.call(row);}
        else{await change(action,row);}
      },itemBuilder:(_)=>[
        if(widget.onManageMembers!=null)const PopupMenuItem(value:'members',child:Text('멤버 관리')),
        if(row['role']=='owner')...const[
        PopupMenuItem(value:'rename-workspace',child:Text('이름변경')),
        PopupMenuItem(value:'delete-workspace',child:Text('삭제')),
      ]else const PopupMenuItem(value:'leave-workspace',child:Text('나가기')),
      ]),
  );
  @override
  Widget build(BuildContext context){
    final owned=rows.where((row)=>row['role']=='owner').toList();
    final joined=rows.where((row)=>row['role']!='owner').toList();
    return PopScope(canPop:!busy,child:AlertDialog(
      title:Row(children:[const Expanded(child:Text('워크스페이스 선택')),
        IconButton(tooltip:'워크스페이스 추가',onPressed:busy?null:()=>change('create-workspace'),icon:const Icon(Icons.add))]),
      content:SizedBox(width:480,child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height*.6),
        child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          if(busy)const LinearProgressIndicator(),
          if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          if(owned.isNotEmpty)...[const Text('소유한 워크스페이스'),...owned.map((row)=>entry(row as Map))],
          if(owned.isNotEmpty&&joined.isNotEmpty)const Divider(),
          if(joined.isNotEmpty)...[const Text('참여 중인 워크스페이스'),...joined.map((row)=>entry(row as Map))],
        ])))),
      actions:[TextButton(onPressed:busy?null:()=>showDialog<void>(context:context,builder:(_)=>DeletedWorkspacesDialog(
        request:widget.request,onRestored:()async{
          final catalog=await widget.request('catalog',{});if(!mounted)return;
          setState(()=>rows=catalog['workspaces'] as List);widget.onCatalog(rows);
        })),child:const Text('삭제된 워크스페이스')),
        TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('닫기'))],
    ));
  }
}

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../inbox/workspace_storage.dart';
import 'workspace_backup.dart';
import 'owned_workspace.dart';

Future<void> exportWorkspaceFile(WorkspaceStorage storage)async{
 await storage.flush();final raw=storage.read()??joinWorkspace({});
 final backup=await WorkspaceBackup.capture(raw,DeviceBackupMedia(),graphs:storage.readGraphLayouts());
 await FilePicker.saveFile(dialogTitle:'데이터 내보내기',fileName:'weaver-${DateTime.now().millisecondsSinceEpoch}.json',mimeType:'application/json',bytes:utf8.encode(backup.encode()));
}
Future<void> importWorkspaceFile(BuildContext context,WorkspaceStorage storage,{WorkspaceSync? sync})async{
 final selected=await FilePicker.pickFiles(type:FileType.custom,allowedExtensions:['json']);
 if(selected.isEmpty)return;
 final bytes=await selected.single.readAsBytes();
 if(bytes.length>WorkspaceBackup.maxCharacters*4)throw const BackupFailure('파일을 읽지 못했거나 파일이 너무 큽니다.');
 final backup=WorkspaceBackup.decode(utf8.decode(bytes));
 if(!context.mounted)return;
 final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('현재 데이터를 덮어쓸까요?'),content:Text(sync==null?'이 기기의 현재 오프라인 공간에 있는 기존 자료가 사라지고 파일 내용으로 대체됩니다. 계속하시겠습니까?':'현재 워크스페이스의 기존 서버 자료와 이 기기의 자료가 사라지고 파일 내용으로 대체됩니다. 다른 참여자에게도 반영됩니다. 계속하시겠습니까?'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('기존 데이터 삭제 후 가져오기'))]));
 if(yes!=true)return;
 await applyWorkspaceBackup(backup,storage,sync:sync);
}
Future<void> applyWorkspaceBackup(WorkspaceBackup backup,WorkspaceStorage storage,{WorkspaceSync? sync,BackupMedia? mediaStore})async{
 final media=mediaStore??DeviceBackupMedia();final staged=await backup.stage(media);
 try{
  await storage.flush();
  if(sync!=null){
   final result=await sync.request('read',{'since':0});
   final remote={for(final row in result['changes'] as List)itemKey(row['kind'],row['id']):Map<String,dynamic>.from(row)};
   final incoming=splitWorkspace(staged.workspace);
   final changes=[for(final key in {...remote.keys,...incoming.keys}){
     ...(incoming[key]??remote[key]!),
     'deleted':!incoming.containsKey(key),'baseRevision':remote[key]?['revision']??0,
   }];
   await sync.uploadMedia(staged.workspace);
   await sync.request('save',{'since':result['revision'],'changes':changes,'replaceContents':true});
   await sync.discardLocalAndPull();
  }else{
   await storage.replaceFromBackup(staged.workspace,graphs:staged.graphs);
  }
  storage.applyServerSnapshot?.call();
 }catch(_){
  // Staged attachments are retained: a lost response may follow a committed server write.
  // The original snapshot is not replaced until the server accepts the import.
  rethrow;
 }
}

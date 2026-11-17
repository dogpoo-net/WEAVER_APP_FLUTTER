import 'dart:convert';
import '../inbox/workspace_storage.dart';
import '../capture/media_storage.dart';
import 'owned_workspace.dart';

class OfflineWorkspace {
  static String owner(String account,String id)=>'$account@offline:$id';
  static String baseline(WorkspaceStorage storage)=>storage.scoped('offline-baseline');
  static bool hasChanges(WorkspaceStorage local)=>local.read()!=null&&local.read()!=local.preferences.getString(baseline(local));
  static Future<void> copyMedia(String raw,String? from,String? to)async{
    final snapshot=WorkspaceSnapshot.decode(raw);
    for(final record in [...snapshot.records,...snapshot.trashRecords]){
      for(final id in [...record.photos.map((p)=>p.id),...record.recordings.map((p)=>p.id)]){
        final bytes=await MediaStorage.read(id,owner:from);
        if(bytes!=null)await MediaStorage.write(id,bytes,owner:to);
      }
    }
  }
  static Future<void> seed(WorkspaceStorage local,WorkspaceStorage source)async{
    if(local.read()!=null&&hasChanges(local))return;
    final raw=source.read()??joinWorkspace({});
    await copyMedia(raw,source.owner,local.owner);
    await local.replaceFromBackup(raw);
    await local.preferences.setString(baseline(local),raw);
  }
  static List<Map<String,dynamic>> delta(WorkspaceStorage local,Map<String,Map<String,dynamic>> remote){
    final before=splitWorkspace(local.preferences.getString(baseline(local))),after=splitWorkspace(local.read());
    return [for(final key in {...before.keys,...after.keys})if(!sameItem(before[key],after[key])){
      ...(after[key]??before[key]!),
      'deleted':!after.containsKey(key),'baseRevision':remote[key]?['revision']??0,
      if((after[key]??before[key])?['kind']=='list:memoBoxes')'previousValue':remote[key]?['value'],
    }];
  }
  static Future<void> publish(WorkspaceStorage local,WorkspaceSync engine)async{
    await local.flush();
    final result=await engine.request('read',{'since':0});
    final remote=<String,Map<String,dynamic>>{};
    for(final row in result['changes'] as List){final item=Map<String,dynamic>.from(row);item['value']=item['payload']==null?null:jsonDecode(item['payload']);remote[itemKey(item['kind'],item['id'])]=item;}
    final changes=delta(local,remote),raw=local.read()!;
    await engine.uploadMedia(raw,sourceOwner:local.owner);
    if(changes.isNotEmpty)await engine.request('save',{'since':result['revision'],'changes':changes});
    await engine.discardLocalAndPull();
    await local.preferences.setString(baseline(local),raw);
  }
}

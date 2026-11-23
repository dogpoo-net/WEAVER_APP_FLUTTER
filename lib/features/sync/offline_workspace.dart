import 'network_recovery.dart';
import 'dart:convert';
import '../auth/email_auth.dart';
import '../inbox/workspace_storage.dart';
import '../capture/media_storage.dart';
import 'owned_workspace.dart';

class OfflineWorkspace {
  static String owner(String account,String id)=>'$account@offline:$id';
  static String baseline(WorkspaceStorage storage)=>storage.scoped('offline-baseline');
  static String activeKey(WorkspaceStorage local)=>local.scoped('offline-active');
  static bool hasChanges(WorkspaceStorage local){
    if(local.read()==null)return false;
    final before=splitWorkspace(local.preferences.getString(baseline(local))),after=splitWorkspace(local.read());
    return NetworkRecoveryPlan(before, after, before).changes.isNotEmpty;
  }
  static Future<void> preserveRecovery(WorkspaceStorage local,WorkspaceStorage online)async{
    final key=local.scoped('offline-recovery');
    // Keep the first available recovery copy until explicitly dealt with.
    if(local.preferences.containsKey(key))return;
    final saved=await local.preferences.setString(key,jsonEncode({
      'savedAt':DateTime.now().toUtc().toIso8601String(),
      'offline':local.read(),'baseline':local.preferences.getString(baseline(local)),
      'online':online.read(),'onlinePrevious':online.preferences.getString('${online.workspaceKey}.previous'),
      'onlineBeforeImport':online.preferences.getString('${online.workspaceKey}.beforeImport'),
      'offlineBeforeImport':local.preferences.getString('${local.workspaceKey}.beforeImport'),
      'onlineCanvasOutbox':online.preferences.getString(online.scoped('canvas.outbox.v1')),
      'onlineGraphs':online.readGraphLayouts(),'offlineGraphs':local.readGraphLayouts(),
    }));
    if(!saved)throw const EmailAuthFailure('복구용 로컬 사본을 보관하지 못했습니다. 자료를 변경하지 않았습니다.');
  }
  static Future<void> copyMedia(String raw,String? from,String? to)async{
    final snapshot=WorkspaceSnapshot.decode(raw);
    for (final id in snapshot.attachmentTypes.keys) {
      final bytes = await MediaStorage.read(id, owner: from);
      if (bytes != null) await MediaStorage.write(id, bytes, owner: to);
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
    final baselineRaw=local.preferences.getString(baseline(local));
    if(baselineRaw==null)throw const EmailAuthFailure('오프라인 작업 전 자료가 없어 안전하게 비교할 수 없습니다. 서버와 로컬 자료를 그대로 보관했습니다.');
    final before=splitWorkspace(baselineRaw),after=splitWorkspace(local.read());
    return NetworkRecoveryPlan(before,after,remote).automatic;
  }

  static Future<bool> publish(WorkspaceStorage local,WorkspaceSync engine)async{
    await local.flush();
    await preserveRecovery(local,engine.storage);
    final result=await engine.request('read',{'since':0});
    final remote=<String,Map<String,dynamic>>{};
    for(final row in result['changes'] as List){final item=Map<String,dynamic>.from(row);item['value']=item['payload']==null?null:jsonDecode(item['payload']);remote[itemKey(item['kind'],item['id'])]=item;}
    final baselineRaw = local.preferences.getString(baseline(local));
    if (baselineRaw == null) throw StateError('오프라인 비교 기준이 없습니다.');
    final raw = local.read()!;
    final plan = NetworkRecoveryPlan(splitWorkspace(baselineRaw), splitWorkspace(raw), remote);
    final changes = plan.automatic;
    if (changes.isNotEmpty) {
      await engine.uploadMedia(joinWorkspace({for (final c in changes)
        if (c['deleted'] != true) itemKey(c['kind'],c['id']): c}), sourceOwner: local.owner);
      await engine.request('save',{'since':result['revision'],'changes':changes,'offlineReconcile':true});
    }
    await engine.discardLocalAndPull();
    if (plan.conflicts.isNotEmpty) return false;
    await local.preferences.setString(baseline(local),raw);
    return true;
  }
}

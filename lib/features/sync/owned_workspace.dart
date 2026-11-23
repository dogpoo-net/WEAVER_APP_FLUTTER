import 'network_recovery.dart';
import 'workspace_events.dart';
import 'document_merge.dart';
import 'dart:async';
import '../inbox/memo_comments.dart';
import 'package:collection/collection.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data' show Uint8List;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../auth/email_auth.dart';
import '../inbox/workspace_storage.dart';
import '../capture/media_storage.dart';

String digest(String text) => sha256.convert(utf8.encode(text)).toString();
String itemKey(String kind, String id) => jsonEncode([kind, id]);
Map<String, Map<String, dynamic>> splitWorkspace(String? raw) {
  final root = raw == null ? <String,dynamic>{'version':1,'elements':[],'trash':[],'notes':[],'colors':{}} : jsonDecode(raw) as Map<String,dynamic>;
  final result=<String,Map<String,dynamic>>{};
  void add(String kind,String id,dynamic value) {result[itemKey(kind,id)]={'kind':kind,'id':id,'value':value};}
  void layout(String scope, Map value, List<String> path) {
    for(final entry in value.entries){final next=[...path,entry.key.toString()];
      if(entry.value is Map){layout(scope,entry.value as Map,next);}else{add('layout',jsonEncode([scope,...next]),entry.value);}
    }
  }
  for(final field in root.entries) {
    final value=field.value;
    if(field.key=='graphLayout' && value is Map){layout('page',value,[]);continue;}
    if(value is List) {
      for(var i=0;i<value.length;i++) {
        final v=value[i];final id=v is Map ? (v['id'] ?? (field.key=='notes'?'legacy-note-${v['createdAt']}-$i':v['createdAt']) ?? v['name'] ?? 'legacy-$i').toString() : v.toString();
        if(field.key=='memoBoxes' && v is Map){final copy=Map<String,dynamic>.from(v);final boxLayout=copy.remove('layout');if(boxLayout is Map)layout('box:$id',boxLayout,[]);add('list:${field.key}',id,copy);}
        else {add('list:${field.key}',id,v);}
      }
    } else if(value is Map) {for(final e in value.entries) {add('map:${field.key}',e.key.toString(),e.value);}}
    else {add('scalar',field.key,value);}
  }
  return result;
}
String joinWorkspace(Map<String,Map<String,dynamic>> items) {
  final result=<String,dynamic>{'version':1,'elements':[],'trash':[],'notes':[],'colors':{}};
  final layouts=<Map<String,dynamic>>[];
  for(final item in items.values) {
    if(item['deleted']==true) continue;
    final kind=item['kind'] as String,id=item['id'] as String,value=item['value'];
    if(kind=='layout'){layouts.add(item);continue;}
    if(kind=='scalar') {result[id]=value;}
    else if(kind.startsWith('list:')) {(result.putIfAbsent(kind.substring(5),()=>[]) as List).add(value);}
    else if(kind.startsWith('map:')) {(result.putIfAbsent(kind.substring(4),()=> <String,dynamic>{}) as Map)[id]=value;}
  }
  for(final item in layouts){
    final path=List<String>.from(jsonDecode(item['id'] as String) as List);final scope=path.removeAt(0);
    Map<String,dynamic>? target;
    if(scope=='page'){target=result.putIfAbsent('graphLayout',()=> <String,dynamic>{}) as Map<String,dynamic>;}
    else {for(final box in (result['memoBoxes'] as List? ?? [])){if('box:${box['name']}'==scope){target=box.putIfAbsent('layout',()=> <String,dynamic>{}) as Map<String,dynamic>;break;}}}
    if(target==null || path.isEmpty)continue;
    for(final segment in path.take(path.length-1)){target=target!.putIfAbsent(segment,()=> <String,dynamic>{}) as Map<String,dynamic>;}
    target![path.last]=item['value'];
  }
  // Newest quick memos first; order is independent from DB row order.
  (result['notes'] as List).sort((a,b)=>(b['createdAt'] as String).compareTo(a['createdAt'] as String));
  return jsonEncode(result);
}
bool sameItem(Map<String,dynamic>? a,Map<String,dynamic>? b) =>
  (a==null || a['deleted']==true) ? (b==null || b['deleted']==true) : b!=null && b['deleted']!=true && const DeepCollectionEquality().equals(a['value'],b['value']);

class OwnedWorkspaces {
  OwnedWorkspaces(this.root);
  final WorkspaceStorage root;
  static const claimKey='weaver.guest.claim.v1';
  static const guestOwnerKey='weaver.guest.owner.v1';
  String newGuest()=> 'guest-${List.generate(24,(_)=>Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join()}';
  WorkspaceStorage scope(String owner)=>WorkspaceStorage(root.preferences,owner:owner);
  Future<void> initialize({int ignoredPendingSaves=0}) async {
    final p=root.preferences;await p.reload();
    if(p.getBool('weaver.owner-migrated.v1')==true)return;
    final raw=root.read();
    if(raw!=null){
      // Unlabelled old data is never guessed to be guest data after session expiry.
      final guest=p.getBool('weaver.guest-mode.v1')==true && !p.containsKey('weaver.test-login.v1');
      final guestOwner=p.getString(guestOwnerKey)??newGuest();
      if(guest && !await p.setString(guestOwnerKey,guestOwner))throw StateError('Guest migration failed');
      final target=scope(guest?guestOwner:'quarantine');
      if(target.read()==null){if(!await p.setString(target.workspaceKey,raw))throw StateError('Migration failed');}
      final graphs=root.readGraphLayouts();if(graphs!=null)await p.setString(target.layoutsKey,graphs);
      WorkspaceSnapshot? legacy;try {legacy=WorkspaceSnapshot.decode(raw);}catch(_) { /* Keep malformed legacy bytes in quarantine for recovery. */ }
      if(legacy!=null)for(final record in [...legacy.records,...legacy.trashRecords]){for(final id in [...record.photos.map((p)=>p.id),...record.recordings.map((p)=>p.id)]){final bytes=await MediaStorage.read(id,owner:null);if(bytes!=null)await MediaStorage.write(id,bytes,owner:target.owner);}}
      for(final suffix in ['.previous','.beforeImport']){final value=p.getString('${WorkspaceStorage.key}$suffix');if(value!=null && !await p.setString('${target.workspaceKey}$suffix',value))throw StateError('Recovery migration failed');}
      if(!await p.setBool('weaver.owner-migrated.v1',true))throw StateError('Migration failed');
      await root.clear();
    }else {if(!await p.setBool('weaver.owner-migrated.v1',true))throw StateError('Migration failed');}
  }
  Future<WorkspaceStorage> guest() async {
    await initialize();final p=root.preferences;await p.reload();
    String? owner=p.getString(guestOwnerKey);final pending=await pendingClaim();
    if(owner==null || pending?['scope']==owner){owner=newGuest();if(!await p.setString(guestOwnerKey,owner))throw StateError('Guest workspace creation failed');}
    return scope(owner);
  }
  Future<Map<String,dynamic>?> pendingClaim() async {
    await root.preferences.reload();final raw=root.preferences.getString(claimKey);
    return raw==null?null:jsonDecode(raw) as Map<String,dynamic>;
  }
  Future<Map<String,dynamic>> sealGuest(String account,WorkspaceStorage guest) async {
    await guest.flush();await root.preferences.reload();
    final existing=await pendingClaim();if(existing!=null)return existing;
    final raw=guest.read();if(raw==null)throw StateError('Empty guest workspace');
    final claim={'account':account,'scope':guest.owner,'guestId':digest(guest.owner!),'sourceHash':digest(raw)};
    if(!await root.preferences.setString(claimKey,jsonEncode(claim)))throw StateError('Guest claim save failed');
    return claim;
  }
  Future<void> finishClaim(Map<String,dynamic> claim) async {
    final source=scope(claim['scope'] as String);
    // Retain the ownership receipt even if cleanup crashes. A fresh guest generation
    // is used afterwards; the completed source can never be re-offered.
    await source.clear();
    if(!await root.preferences.setString('weaver.guest.receipt.${claim['guestId']}',claim['account'] as String))throw StateError('Receipt save failed');
    if(!await root.preferences.remove(claimKey))throw StateError('Guest cleanup failed');
  }
}

String? editResource(Map<String,dynamic>? item) {
  if (item == null) return null;
  if (item['kind'] == 'layout') {
    final path = jsonDecode(item['id'] as String) as List;
    return path.length > 1 && path[1] == 'blocks' ? 'canvas:boxes' : null;
  }
  final value = item['value'];
  return item['kind'] == 'list:notes' && value is Map && value['project'] is Map ? value['project']['id'] as String? : null;
}

// Viewport/search are device-local. Geometry is synchronized per leaf item.
bool sharedCanvasItem(Map<String,dynamic>? item) {
  if(item?['kind']!='layout')return false;
  final path=jsonDecode(item!['id'] as String) as List;
  return !{'viewport','query','hideTags'}.contains(path.last);
}
bool localCanvasView(Map<String,dynamic>? item)=>item?['kind']=='layout'&&!sharedCanvasItem(item);

class WorkspaceSync extends ChangeNotifier {
  WorkspaceSync(this.storage,this.api,{required this.isCurrent,this.workspaceId,this.readOnly=false}) { memoCommentCounts.value={}; }
  final WorkspaceStorage storage;
  final EmailAuthApi api;
  final String? workspaceId;final bool readOnly;
  final documentLeases=<String,String>{};
  final observedLeases=<String,String>{};
  final lostLeases=<String>{};
  int? _observedRevision;
  int _leaseEpoch=0;
  Future<Map<String,dynamic>> documentLease(String id,String token,bool release) async {
    _leaseEpoch++;
    if(release){
      try{return await request('document-lease',{'documentId':id,'leaseToken':token,'release':true});}
      finally{_leaseEpoch++;if(observedLeases[id]==token){observedLeases.remove(id);documentLeases.remove(id);lostLeases.remove(id);storage.leaseStates.remove(id);_observedRevision=null;}}
    }
    final renewing=observedLeases[id]==token;
    if (renewing && lostLeases.contains(id)) return {'acquired':false};
    observedLeases[id]=token;
    final result=await request('document-lease',{'documentId':id,'leaseToken':token,'renewOnly':renewing});
    _leaseEpoch++;
    if(observedLeases[id]==token)_acceptLease(id,token,result);
    return result;
  }
  Future<Map<String,dynamic>> inspectLease(String id,String token) => _documentLeaseMode(id,token,true);
  Future<Map<String,dynamic>> acquireLease(String id,String token) => _documentLeaseMode(id,token,false);
  Future<Map<String,dynamic>> _documentLeaseMode(String id,String token,bool observe) async {
    _leaseEpoch++;observedLeases[id]=token;
    final result=await request('document-lease',{'documentId':id,'leaseToken':token,if(observe)'observeOnly':true});
    _leaseEpoch++;if(observedLeases[id]==token)_acceptLease(id,token,result);
    return result;
  }
  void _acceptLease(String id,String token,Map<String,dynamic> result){
    storage.leaseStates[id]=result;
    if(result['acquired']==true){documentLeases[id]=token;lostLeases.remove(id);}
    else {documentLeases.remove(id);if(result['available']==true){lostLeases.remove(id);}else{lostLeases.add(id);}}
    storage.leaseChanges.value++;
  }
  Future<Map<String,dynamic>> takeLease(String id,String token) async {
    _leaseEpoch++;observedLeases[id]=token;
    final result=await request('document-lease',{'documentId':id,'leaseToken':token,'takeover':true});
    _leaseEpoch++;_acceptLease(id,token,result);

    return result;
  }
  Future<bool>? _statusRequest;
  Future<bool> checkRemote() => _statusRequest ??= _checkRemote()
      .whenComplete(() => _statusRequest = null);
  Future<bool> _checkRemote() async {
    if(networkPending){await recoverNetwork();return false;}
    if(manualReview)return false;
    final leaseEpoch=_leaseEpoch;
    late final Map<String,dynamic> result;
    try{result=await request('status',{'documentLeases':observedLeases});}
    catch(_){storage.canvasSaveState.value='연결 대기';rethrow;}
    if(storage.canvasSaveState.value=='연결 대기'&&!_canvasPending)storage.canvasSaveState.value='저장됨';
    if(leaseEpoch==_leaseEpoch)for(final entry in ((result['leases'] as Map?)??{}).entries){final id=entry.key as String;final token=observedLeases[id];if(token!=null)_acceptLease(id,token,Map<String,dynamic>.from(entry.value as Map));}
    final revision=result['revision'] as int;
    if(_observedRevision==revision)return false;
    return revision!=cursor;
  }
  Future<void> reloadResource(String id)=>_rebaseResource(id,discard:true);
  Future<void> _rebaseResource(String id,{required bool discard}) async {
    while(_running!=null){await _running;}
    await (_running=(() async {
      final result=await request('read',{'since':0});
      await storage.flush();final local=splitWorkspace(storage.read());
      final remote=<String,Map<String,dynamic>>{};
      for(final raw in result['changes'] as List){final item=Map<String,dynamic>.from(raw as Map);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);remote[itemKey(item['kind'],item['id'])]=item;}
      for(final key in {...base.keys,...local.keys,...remote.keys}){
        if(editResource(local[key])!=id && editResource(base[key])!=id && editResource(remote[key])!=id)continue;
        if(remote[key]==null){base.remove(key);}else{base[key]=remote[key]!;}
        if(discard){if(remote[key]==null || remote[key]!['deleted']==true){local.remove(key);}else{local[key]=remote[key]!;}}
      }
      if(discard){await storage.replaceFromBackup(joinWorkspace(local));_observedRevision=null;}
      await saveBase();
    })().whenComplete(()=>_running=null));
  }
  Future<void> settle()async{try{await _running;}catch(_){} }
  final bool Function() isCurrent;
  Map<String,Map<String,dynamic>> base={};
  int cursor=0;
  int _pendingSaves=0;
  String? error;
  bool busy=false,ready=false,_disposed=false;
  Future<void>? _running;
  String? _lastSynced;
  void changed(){if(!_disposed)notifyListeners();}
  String get recoveryKey=>storage.scoped('network-recovery-base');
  bool get networkPending=>storage.preferences.containsKey(recoveryKey);
  bool needsRecoveryReview=false,_recovering=false;
  Timer? _networkTimer;
  Map<String,Map<String,dynamic>> get recoveryBase {
    final raw=storage.preferences.getString(recoveryKey);
    return raw==null?base:{for(final e in (jsonDecode(raw) as Map).entries)e.key as String:Map<String,dynamic>.from(e.value as Map)};
  }
  Future<void> enterNetworkOffline()async{
    if(_disposed||!isCurrent())return;
    if(!networkPending && !await storage.preferences.setString(recoveryKey,jsonEncode(base)))throw StateError('오프라인 기준 저장 실패');
    storage.offlineMode=true;error=null;_canvasTimer?.cancel();
    storage.canvasSaveState.value='오프라인 · 이 기기에 저장됨';
    _networkTimer??=Timer.periodic(const Duration(seconds:10),(_)=>recoverNetwork());
    changed();
  }
  Future<void> completeNetworkRecovery()async{
    await storage.preferences.remove(recoveryKey);storage.offlineMode=false;needsRecoveryReview=false;
    _networkTimer?.cancel();_networkTimer=null;error=null;storage.canvasSaveState.value='저장됨';changed();schedule();
  }
  Future<void> recoverNetwork()async{
    if(_disposed||!isCurrent()||!networkPending||_recovering||manualReview||storage.canvasInteracting||storage.hasUnsavedInput?.call()==true)return;

    _recovering=true;
    try{
      await settle();await storage.flush();
      final result=await request('read',{'since':0});
      if(_disposed||!isCurrent()||storage.canvasInteracting||storage.hasUnsavedInput?.call()==true)return;
      await storage.flush();final snapshot=storage.read();final local=splitWorkspace(snapshot);
      final remote=<String,Map<String,dynamic>>{};
      for(final raw in result['changes'] as List){final item=Map<String,dynamic>.from(raw);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload'));remote[itemKey(item['kind'],item['id'])]=item;}
      final plan=NetworkRecoveryPlan(recoveryBase,local,remote);
      final automatic = plan.automatic;
      var latest=result;
      if(automatic.isNotEmpty&&!readOnly){
        await uploadMedia(joinWorkspace({for(final c in automatic)if(c['deleted']!=true)itemKey(c['kind'],c['id']):c}));
        if(storage.read()!=snapshot)return;
        latest=await request('save',{'since':result['revision'],'offlineReconcile':true,'changes':automatic});
        for(final raw in latest['changes'] as List){final item=Map<String,dynamic>.from(raw);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload'));remote[itemKey(item['kind'],item['id'])]=item;}
      }
      if(plan.conflicts.isNotEmpty){needsRecoveryReview=true;storage.canvasSaveState.value='동기화 확인 필요';changed();return;}
      // Edits made while the acknowledgement was in flight stay local for the next pass.
      await storage.flush();final current=splitWorkspace(storage.read());
      final displayed=NetworkRecoveryPlan(local,current,remote).merged;
      if(storage.canvasInteracting||storage.hasUnsavedInput?.call()==true)return;
      await ensureMedia(joinWorkspace(remote));
      await storage.flush();
      if(storage.read()!=joinWorkspace(current)&&!const DeepCollectionEquality().equals(splitWorkspace(storage.read()),current))return;
      if(storage.canvasInteracting||storage.hasUnsavedInput?.call()==true)return;
      if(_disposed||!isCurrent())return;
      await storage.replaceFromBackup(joinWorkspace(displayed));
      base=remote;cursor=latest['revision'] as int;_lastSynced=joinWorkspace(base);await saveBase();
      await storage.preferences.remove(_canvasOutbox);
      storage.applyServerSnapshot?.call();ready=true;
      if(!const DeepCollectionEquality().equals(current,local)){
        await storage.preferences.setString(recoveryKey,jsonEncode(base));return;
      }
      await completeNetworkRecovery();
    }catch(e){
      if(e is EmailAuthFailure&&e.status==409){storage.canvasSaveState.value='동기화 재시도 중';}
      else if(e is! EmailAuthFailure||!e.networkUnavailable){error=e.toString();}
      changed();
    }finally{_recovering=false;}
  }
  bool manualReview=false;
  Future<void> beginReview()async{manualReview=true;_canvasTimer?.cancel();await settle();await storage.flush();}
  void endReview(){manualReview=false;schedule();}
  Timer? _canvasTimer;
  String get _canvasOutbox=>storage.scoped('canvas.outbox.v1');
  bool get _canvasPending {
    if(storage.preferences.containsKey(_canvasOutbox))return true;
    final local=splitWorkspace(storage.read());
    return {...base.keys,...local.keys}.any((key)=>sharedCanvasItem(local[key]??base[key])&&!sameItem(local[key],base[key]));
  }
  void schedule(){
    changed();
    if(networkPending || manualReview || _disposed || readOnly || !_canvasPending)return;
    storage.canvasSaveState.value='저장 중';
    _canvasTimer?.cancel();
    _canvasTimer=Timer(const Duration(milliseconds:750),_autoCanvas);
  }
  Future<void> _autoCanvas()async{
    if(_disposed || !isCurrent())return;
    if(storage.canvasInteracting){schedule();return;}
    try{await flushCanvas();}catch(_){
      if(!_disposed)_canvasTimer=Timer(const Duration(seconds:5),_autoCanvas);
    }
  }
  Future<void> flushCanvas()async{
    _canvasTimer?.cancel();
    while(_running!=null){await _running;}
    if(networkPending || manualReview || _disposed || readOnly || !isCurrent())return;
    try{await (_running=_flushCanvas().whenComplete(()=>_running=null));}
    catch(_){if(networkPending)return;if(!_disposed)_canvasTimer=Timer(const Duration(seconds:5),_autoCanvas);rethrow;}
    if(_canvasPending)schedule();
  }
  Future<void> _flushCanvas()async{
    if(networkPending)return;
    try{
      await storage.flush();
      final pending=storage.preferences.getString(_canvasOutbox);
      Map<String,dynamic> body;
      if(pending!=null){body=jsonDecode(pending) as Map<String,dynamic>;}else{
        final local=splitWorkspace(storage.read());
        final changes=<Map<String,dynamic>>[];
        for(final key in {...base.keys,...local.keys}){
          final item=local[key]??base[key]!;
          if(!sharedCanvasItem(item)||sameItem(local[key],base[key]))continue;
          changes.add({'kind':item['kind'],'id':item['id'],'value':local[key]?['value'],'deleted':local[key]==null,'baseRevision':base[key]?['revision']??0});
        }
        if(changes.isEmpty){storage.canvasSaveState.value='저장됨';return;}
        body={'since':cursor,'canvasOperationId':digest('${DateTime.now().microsecondsSinceEpoch}:${Random.secure().nextDouble()}'),'changes':changes};
        if(!await storage.preferences.setString(_canvasOutbox,jsonEncode(body)))throw StateError('Canvas outbox save failed');
      }
      storage.canvasSaveState.value='저장 중';
      final result=await request('save',body);
      await storage.flush();
      final current=splitWorkspace(storage.read());
      var snapshotChanged=false;
      final submitted={for(final c in body['changes'] as List)itemKey(c['kind'],c['id']):Map<String,dynamic>.from(c as Map)};
      for(final row in result['changes'] as List){
        final item=Map<String,dynamic>.from(row as Map);
        final key=itemKey(item['kind'],item['id']);
        if(!submitted.containsKey(key))continue;
        item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);
        base[key]=item;
        // Acknowledgement cannot replace a newer local drag.
        if(sameItem(current[key],submitted[key])&&!sameItem(current[key],item)){
          snapshotChanged=true;
          if(item['deleted']==true){current.remove(key);}else{current[key]=item;}
        }
      }
      if(snapshotChanged)await storage.replaceFromBackup(joinWorkspace(current));
      await saveBase();
      if(!await storage.preferences.remove(_canvasOutbox))throw StateError('Canvas receipt save failed');
      if(snapshotChanged)storage.applyServerSnapshot?.call();
      storage.canvasSaveState.value='저장됨';error=null;
    }catch(e){storage.canvasSaveState.value='연결 대기';rethrow;}
  }
  Future<Map<String,dynamic>> request(String action,Map<String,Object?> body) async {
    if(_disposed || !isCurrent())throw const EmailAuthFailure('계정이 변경되었습니다.');
    if(readOnly && {'save','claim','media/write','document-lease','comments/write'}.contains(action))throw const EmailAuthFailure('읽기 전용 워크스페이스입니다.');
    if(networkPending && !_recovering && !manualReview && {'save','claim','media/write','comments/write'}.contains(action))throw const EmailAuthFailure('오프라인 변경을 먼저 동기화해주세요.');
    late Map<String,dynamic> result;
    try{result=await api.workspace(action,{...body,if(workspaceId!=null)'workspaceId':workspaceId});}
    on EmailAuthFailure catch(e){if(e.networkUnavailable)await enterNetworkOffline();rethrow;}
    if(_disposed || !isCurrent())throw const EmailAuthFailure('계정이 변경되었습니다.');
    if(result['commentCounts'] is Map){final counts=(result['commentCounts'] as Map).map((key,value)=>MapEntry(key.toString(),(value as num).toInt()));if(!mapEquals(counts,memoCommentCounts.value))memoCommentCounts.value=counts;}
    return result;
  }
  void loadBase(){
    final raw=storage.preferences.getString(storage.syncKey);if(raw==null)return;
    final state=jsonDecode(raw) as Map;cursor=state['metadataVersion']==1?state['cursor'] as int:0;
    base={for(final e in (state['items'] as Map).entries)e.key as String:Map<String,dynamic>.from(e.value as Map)};
    _lastSynced=state['snapshot'] as String?;
  }
  Future<void> saveBase() async {
    if(!await storage.preferences.setString(storage.syncKey,jsonEncode({'metadataVersion':1,'cursor':cursor,'items':base,'snapshot':_lastSynced})))throw StateError('Sync checkpoint failed');
  }
  void accept(Map<String,dynamic> result){
    for(final raw in result['changes'] as List){final item=Map<String,dynamic>.from(raw as Map);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);base[itemKey(item['kind'],item['id'])]=item;}
    cursor=result['revision'] as int;
  }
  late final Future<Uint8List?> Function(String) _readAttachment = (id) async {
    try {
      final result = await request('media/read', {'mediaId': id});
      return base64Decode(result['data'] as String);
    } on EmailAuthFailure {
      // A missing or temporarily unavailable attachment can be opened again.
      return null;
    }
  };

  Future<void> ensureMedia(String raw) async {
    final snapshot=WorkspaceSnapshot.decode(raw);
    final ids = snapshot.attachmentTypes.keys;
    final owner = storage.owner;
    for (final id in ids) {
      if (await MediaStorage.contains(id, owner: owner)) continue;
      final result = await request('media/read', {'mediaId': id});
      await MediaStorage.write(id, base64Decode(result['data'] as String), owner: owner);
    }
  }
  Future<void> uploadMedia(String raw,{String? sourceOwner}) async {
    final snapshot=WorkspaceSnapshot.decode(raw);
    for (final entry in snapshot.attachmentTypes.entries) {
      final id = entry.key;
      final flag = storage.scoped('media-sent.$id');
      if (storage.preferences.getBool(flag) == true ||
          (base[itemKey('list:workspacePhotos', id)]?['deleted'] == false)) continue;
      final bytes = await MediaStorage.read(id, owner: sourceOwner ?? storage.owner);
      if (bytes == null) throw const EmailAuthFailure('첨부파일을 읽지 못했습니다. 로컬 자료를 보존합니다.');
      await request('media/write', {'mediaId': id, 'mediaType': entry.value, 'data': base64Encode(bytes)});
      await storage.preferences.setBool(flag, true);
    }
  }

  Future<void> initialize({int ignoredPendingSaves=0,bool serverCanvas=false}) async {
    if(manualReview)return;
    loadBase();
    final beforeRead=splitWorkspace(storage.read());
    final initialBase=Map<String,Map<String,dynamic>>.from(base),wasPending=networkPending;
    try {
      if(networkPending){await enterNetworkOffline();throw const EmailAuthFailure('오프라인 변경을 보관 중입니다.');}
      Map<String,dynamic> result;
      try{result=await request('read',{'since':cursor});}
      on EmailAuthFailure catch(e){if(e.status!=409)rethrow;result=await request('read',{'since':0});base.clear();}
      await storage.flush();
      final local=splitWorkspace(storage.read());
      final previousBase=Map<String,Map<String,dynamic>>.from(base);
      accept(result);
      final displayed=Map<String,Map<String,dynamic>>.from(base);
      displayed.removeWhere((_,item)=>storage.editorResources.contains(editResource(item)));
      for(final entry in local.entries){if(storage.editorResources.contains(editResource(entry.value)))displayed[entry.key]=entry.value;}
      // A server response must not undo edits made while it was in flight,
      // or an explicit save already waiting behind this read.
      for(final key in {...beforeRead.keys,...local.keys,...previousBase.keys}){
        if((!serverCanvas && !readOnly && sharedCanvasItem(local[key]??previousBase[key]) && !sameItem(local[key],previousBase[key])) || localCanvasView(local[key]) || !sameItem(local[key],beforeRead[key]) || (_pendingSaves>ignoredPendingSaves && !sameItem(local[key],previousBase[key]))){
          if(local[key]==null){displayed.remove(key);}else{displayed[key]=local[key]!;}
        }
      }
      // A box move has two parts. Canvas leaves are queued separately from
      // the parent change, so a refresh must preserve the unsent parent too.
      if (!readOnly && !serverCanvas) {
        // A browse refresh can start after local deletion but before its save.
        // Keep the removal while accepting unrelated edits from other devices.
        for (final entry in previousBase.entries) {
          final prior = entry.value;
          if (prior['deleted'] == true) continue;
          if (prior['kind'] == 'list:workspacePhotos' && !local.containsKey(entry.key)) {
            displayed.remove(entry.key);
          }
          if (prior['kind'] != 'list:elements') continue;
          final before = prior['value']?['photos'] as List?;
          final current = local[entry.key]?['value'];
          final remote = displayed[entry.key];
          if (before == null || current is! Map || remote?['value'] is! Map) continue;
          final remaining = {for (final photo in current['photos'] as List? ?? []) photo['id']};
          final removed = {for (final photo in before) if (!remaining.contains(photo['id'])) photo['id']};
          final value = remote!['value'] as Map;
          if (removed.isEmpty || value['photos'] is! List) continue;
          displayed[entry.key] = {
            ...remote,
            'value': {...value, 'photos': [
              for (final photo in value['photos']) if (!removed.contains(photo['id'])) photo,
            ]},
          };
        }
        for (final entry in local.entries) {
          final item = entry.value;
          final prior = previousBase[entry.key]?['value'];
          final remote = displayed[entry.key];
          final proposed = item['value'];
          if (item['kind'] != 'list:memoBoxes' || prior is! Map ||
              proposed is! Map || remote == null || remote['deleted'] == true ||
              remote['value'] is! Map || prior['folder'] == proposed['folder']) {
            continue;
          }
          displayed[entry.key] = {
            ...remote,
            'value': {...remote['value'] as Map, 'folder': proposed['folder']},
          };
        }
      }
      final raw = joinWorkspace(displayed);
      if (serverCanvas || storage.read() == null ||
          {...local.keys, ...displayed.keys}.any((key) => !sameItem(local[key], displayed[key]))) {
        await storage.replaceFromBackup(raw);
      }
      if(serverCanvas)await storage.preferences.remove(_canvasOutbox);
      _lastSynced=joinWorkspace(base);
      await saveBase();_observedRevision=result['revision'] as int;ready=true;error=null;
    }catch(e){if(networkPending&&!wasPending){base=initialBase;await storage.preferences.setString(recoveryKey,jsonEncode(base));}error=networkPending?null:e.toString();}
    final attachmentOwner = storage.owner;
    if (!_disposed && isCurrent() && attachmentOwner != null) {
      MediaStorage.remoteReaders[attachmentOwner] = _readAttachment;
    }
    storage.canvasWritable=!readOnly;storage.syncCanvas=flushCanvas;
    storage.itemMetadata=(kind,id)=>base[itemKey(kind,id)];
    storage.comments=request;storage.commentsWritable=!readOnly;
    storage.watchRemote=(change,connection)=>WorkspaceEvents(open:(client)=>api.workspaceEvents(client,workspaceId),onChange:change,onConnection:connection);
    storage.onChanged=schedule;storage.syncNow=flush;storage.syncDeleted=flushDeletions;storage.syncFolders=flushFolders;storage.refreshNow=refreshFromServer;storage.checkRemote=checkRemote;storage.syncContent=readOnly?null:()=>_enqueueFlush(false,contentOnly:true);storage.syncResource=(id)=>id.startsWith('canvas:')?flushCanvas():saveDocument(id);storage.reloadResource=reloadResource;storage.takeLease=takeLease;storage.inspectLease=inspectLease;storage.acquireLease=acquireLease;
    changed();if(storage.read()!=_lastSynced)schedule();
  }
  Future<void>? _refreshRequest;
  Future<void> refreshFromServer() => _refreshRequest ??= _refreshFromServer()
      .whenComplete(() => _refreshRequest = null);
  Future<void> _refreshFromServer() async {
    if(networkPending){await recoverNetwork();return;}
    while (_running != null) { await _running; }
    final previous = Map<String,Map<String,dynamic>>.from(base), oldCursor = cursor;
    final oldSnapshot = _lastSynced;
    await (_running = initialize().whenComplete(() => _running = null));
    if (error != null) { base = previous; cursor = oldCursor; _lastSynced = oldSnapshot; throw EmailAuthFailure(error!); }
  }
  final _unacknowledgedDocuments = <String, Map<String, dynamic>>{};

  bool _sameDocumentContent(Map<String, dynamic> left, Map<String, dynamic> right) {
    final leftTags = Set<String>.from(left['project']['tags'] as List? ?? []);
    final rightTags = Set<String>.from(right['project']['tags'] as List? ?? []);
    return documentSegment(left).signature == documentSegment(right).signature &&
        setEquals(leftTags, rightTags);
  }

  Future<void> saveDocument(String id)async{
    if(networkPending){await storage.flush();return;}
    await storage.flush();
    while(_running!=null){await _running;}
    try{await (_running=_saveDocument(id).whenComplete(()=>_running=null));}catch(_){if(!networkPending)rethrow;}
  }
  Future<void> _saveDocument(String id)async{
    if(networkPending)return;
    storage.lastSaveReplaced=false;
    final local=splitWorkspace(storage.read());
    final entry=local.entries.where((e)=>e.value['kind']=='list:notes'&&editResource(e.value)==id).firstOrNull;
    if(entry==null)throw const EmailAuthFailure('저장할 문서를 찾지 못했습니다.');
    var candidate=Map<String,dynamic>.from(entry.value['value'] as Map);
    var expected=storage.documentSaveBases.containsKey(id)?storage.documentSaveBases[id]:base[entry.key];
    final unacknowledged = _unacknowledgedDocuments[id];
    for(var attempt=0;attempt<5;attempt++){
      _unacknowledgedDocuments[id] = candidate;
      final result=await request('save',{'resourceId':id,'documentMerge':true,'changes':[{'kind':entry.value['kind'],'id':entry.value['id'],'value':candidate,'baseRevision':expected?['revision']??0,'deleted':false}]});
      if(result['documentConflict'] is Map){
        final remote=Map<String,dynamic>.from(result['documentConflict'] as Map);
        if(remote['deleted']==true)throw const EmailAuthFailure('다른 기기에서 삭제된 문서입니다. 로컬 초안은 보관됩니다.');
        remote['value']=jsonDecode(remote.remove('payload') as String);
        // A failed response can leave the user's previous save committed.
        // Only use it as the ancestor when the returned content matches it.
        final remoteValue = Map<String, dynamic>.from(remote['value'] as Map);
        final ancestor = unacknowledged != null &&
            _sameDocumentContent(unacknowledged, remoteValue)
            ? unacknowledged
            : expected?['value'];
        if (unacknowledged == null) _unacknowledgedDocuments.remove(id);
        else _unacknowledgedDocuments[id] = unacknowledged;
        if(ancestor is! Map)throw const EmailAuthFailure('문서의 원본 버전을 찾지 못했습니다. 로컬 초안은 보관됩니다.');
        final plan=mergeDocument(Map<String,dynamic>.from(ancestor),candidate,Map<String,dynamic>.from(remote['value'] as Map));
        if(plan.hasConflicts)throw DocumentMergeConflict(plan,remote);
        candidate=plan.resolve();expected=remote;continue;
      }
      final row=Map<String,dynamic>.from((result['changes'] as List).single as Map);
      row['value']=jsonDecode(row.remove('payload') as String);
      _unacknowledgedDocuments.remove(id);
      base[entry.key]=row;storage.documentSaveBases[id]=row;
      await storage.flush();final current=splitWorkspace(storage.read());current[entry.key]=row;
      await storage.replaceFromBackup(joinWorkspace(current));await saveBase();
      storage.applyServerSnapshot?.call();error=null;return;
    }
    throw const EmailAuthFailure('다른 사용자의 저장이 계속되고 있습니다. 초안을 보관했으니 다시 저장해주세요.');
  }
  Future<void> flushFolders() => _enqueueFlush(false, foldersOnly: true);
  Future<void> flush() async {await flushCanvas();await _enqueueFlush(false);}
  Future<void> flushDeletions() => _enqueueFlush(true);
  Future<void> _enqueueFlush(bool deletionsOnly, {bool foldersOnly = false, bool contentOnly=false, String? resource}) async {
    if(networkPending||manualReview){await storage.flush();return;}
    // Capture explicit saves before waiting for an in-flight server read.
    await storage.flush();
    final requestedSnapshot=storage.read();
    _pendingSaves++;
    try {
      while (_running != null) { await _running; }
      await (_running = _flush(deletionsOnly: deletionsOnly, foldersOnly: foldersOnly, contentOnly:contentOnly, resource:resource, requestedSnapshot:requestedSnapshot).whenComplete(() => _running = null));
      if(error!=null&&!networkPending)throw EmailAuthFailure(error!);
    } finally {_pendingSaves--; }
  }
  Future<void> _flush({bool deletionsOnly = false, bool foldersOnly = false, bool contentOnly=false, String? resource, String? requestedSnapshot}) async {
    if(networkPending||_disposed || !isCurrent())return;
    storage.lastSaveReplaced=false;busy=true;changed();
    try {
      await storage.flush();
      if(!ready){await initialize();if(!ready)return;}
      final raw=requestedSnapshot??storage.read();if(raw==null)return;
      final local=splitWorkspace(raw);final changes=<Map<String,dynamic>>[];
      var skippedOpenDocument = false;
      for(final key in {...base.keys,...local.keys}){
        if(resource==null && sameItem(local[key],base[key]))continue;
        final item=local[key]??base[key]!;
        if(resource==null && item['kind']=='layout')continue;
        final scope=editResource(item)??editResource(base[key]);
        if(contentOnly && scope!=null)continue;
        if(resource!=null && scope!=resource)continue;
        if (!foldersOnly && scope != null && storage.editorResources.contains(scope)) {
          skippedOpenDocument = true;
          continue;
        }
        if (deletionsOnly) {
          final kind = item['kind'];
          final removed = !local.containsKey(key) && {'list:elements','list:notes','list:trash','list:memoBoxes'}.contains(kind);
          final trashed = kind == 'list:trash' && local.containsKey(key) &&
            !local.containsKey(itemKey('list:elements', item['id'] as String));
          final unusedColor = kind == 'map:colors' && !local.containsKey(key) && !local.values.any((v) => {'list:elements','list:trash'}.contains(v['kind']) && v['value'] is Map && v['value']['text'] == item['id']);
          if (!removed && !trashed && !unusedColor) continue;
        }
        var value = local[key]?['value'];
        if (foldersOnly) {
          final kind = item['kind'] as String;
          final folderList = {'list:folders','list:paragraphFolders','list:elementFolders','list:hashtagFolders','list:memoBoxFolders','map:memoBoxFolderParents','map:hashtagFolderAssignments'}.contains(kind);
          if (!folderList) {
            if (!{'list:notes','list:elements','list:memoBoxes'}.contains(kind) || base[key]?['deleted'] == true || base[key]?['value'] is! Map || value is! Map) continue;
            final previous = base[key]!['value'] as Map;
            final folderChanged = previous['folder'] != value['folder'] || (previous['project'] is Map && value['project'] is Map && previous['project']['folder'] != value['project']['folder']);
            if (!folderChanged) continue;
            final copy = jsonDecode(jsonEncode(previous)) as Map<String,dynamic>;
            copy['folder'] = value['folder'];
            if (copy['project'] is Map && value['project'] is Map) copy['project']['folder'] = value['project']['folder'];
            if (jsonEncode(copy) == jsonEncode(previous)) continue;
            value = copy;
          }
        }
        changes.add({'kind':item['kind'],'id':item['id'],'value':value,'deleted':!local.containsKey(key),'baseRevision':base[key]?['revision']??0,if(item['kind']=='list:memoBoxes')'previousValue':base[key]?['value']});
      }
      if(changes.isNotEmpty || resource!=null){
        if (!deletionsOnly && !foldersOnly) { await uploadMedia(raw); }
        else { await uploadMedia(joinWorkspace({for (final c in changes) if (c['kind'] == 'list:trash' && c['deleted'] != true) itemKey(c['kind'],c['id']): c})); }
        final result=await request('save',{'since':cursor,'changes':changes,'documentLeases':documentLeases,'resourceId':resource,'releaseAfterSave':resource!=null&&!resource.startsWith('canvas:')});
        // Only acknowledge the submitted local snapshot. Remote-only edits are
        // fetched on the next workspace open, not applied over an active editor.
        final returned={for(final row in result['changes'] as List)itemKey(row['kind'],row['id']):row};
        for(final c in changes){final key=itemKey(c['kind'],c['id']);base[key]={...c,'revision':returned[key]?['revision']??result['revision'],'author':returned[key]?['author'],'authorId':returned[key]?['authorId'],'updatedAt':returned[key]?['updatedAt']};}
        final mergedBoxes=returned.values.where((row)=>row['kind']=='list:memoBoxes').toList();
        if(mergedBoxes.isNotEmpty){
          await storage.flush();final current=splitWorkspace(storage.read());var updated=false;
          for(final row in mergedBoxes){final item=Map<String,dynamic>.from(row as Map);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);final key=itemKey(item['kind'],item['id']);
            final submitted=local[key];base[key]=item;
            if(sameItem(current[key],submitted)&&!sameItem(current[key],item)){if(item['deleted']==true){current.remove(key);}else{current[key]=item;}updated=true;}
          }
          if(updated){await storage.replaceFromBackup(joinWorkspace(current));storage.applyServerSnapshot?.call();}
        }
        if(resource!=null){
          for(final row in returned.values){final item=Map<String,dynamic>.from(row as Map);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);base[itemKey(item['kind'],item['id'])]=item;}
          final current=splitWorkspace(storage.read())..removeWhere((_,item)=>editResource(item)==resource);
          for(final entry in base.entries){if(entry.value['deleted']!=true && editResource(entry.value)==resource)current[entry.key]=entry.value;}
          await storage.replaceFromBackup(joinWorkspace(current));storage.applyServerSnapshot?.call();
        }

      }
      if ((!skippedOpenDocument && !deletionsOnly && !foldersOnly && !contentOnly && resource==null) || {...base.keys,...local.keys}.every((key) => sameItem(local[key],base[key]))) _lastSynced=raw;
      await saveBase();error=null;
    }catch(e){
      if(e is EmailAuthFailure && e.status==409){
        await initialize(ignoredPendingSaves:1);
        if(error==null){storage.lastSaveReplaced=true;storage.applyServerSnapshot?.call();}
      }else{error=networkPending?null:e.toString();}
    }
    finally {busy=false;changed();if(!_disposed && error==null && storage.read()!=_lastSynced)schedule();}
  }
  Future<void> importGuest(OwnedWorkspaces owned,Map<String,dynamic> claim) async {
    if(claim['account']!=storage.owner?.split('@workspace:').first)throw const EmailAuthFailure('비회원 자료는 가져오기를 시작한 계정에만 복구할 수 있습니다.');
    // Preserve this account's pending edits before merging a guest source.
    // Re-read on retry to recover a server commit whose local checkpoint failed.
    await initialize();if(!ready)throw EmailAuthFailure(error??'자료를 불러오지 못했습니다.');await flush();
    final guest=owned.scope(claim['scope'] as String);final raw=guest.read();
    if(raw==null){await owned.finishClaim(claim);return;}
    if(digest(raw)!=claim['sourceHash'])throw const EmailAuthFailure('비회원 자료가 변경되었습니다. 자료를 보존했습니다.');
    final records=splitWorkspace(raw);final changes=<Map<String,dynamic>>[];
    for(final entry in records.entries){final previous=base[entry.key];
      if(previous!=null && previous['deleted']!=true){
        if(sameItem(previous,entry.value))continue;
        if(entry.value['kind']=='list:memoBoxes'){
          final merged=Map<String,dynamic>.from(previous['value'] as Map);merged['ids']=<dynamic>{...(merged['ids'] as List? ?? []),...((entry.value['value'] as Map)['ids'] as List? ?? [])}.toList();
          changes.add({...entry.value,'value':merged,'baseRevision':previous['revision'],'deleted':false});continue;
        }
        // Existing account settings win; content identity collisions never overwrite.
        if(!entry.value['kind'].toString().startsWith('list:elements') && !entry.value['kind'].toString().startsWith('list:notes') && !entry.value['kind'].toString().startsWith('list:trash'))continue;
        throw const EmailAuthFailure('같은 식별자의 자료가 계정에 존재합니다. 비회원 자료를 보관했습니다.');
      }
      changes.add({...entry.value,'baseRevision':previous?['revision']??0,'deleted':false});
    }
    await uploadMedia(raw,sourceOwner:guest.owner);
    final result=await request('claim',{'since':0,'guestId':claim['guestId'],'sourceHash':claim['sourceHash'],'changes':changes});
    final previous=Map<String,Map<String,dynamic>>.from(base),previousCursor=cursor,previousSnapshot=_lastSynced;
    try{base.clear();accept(result);final combined=joinWorkspace(base);await ensureMedia(combined);
      await storage.replaceFromBackup(combined);_lastSynced=combined;await saveBase();
    }catch(_){base=previous;cursor=previousCursor;_lastSynced=previousSnapshot;rethrow;}
    await owned.finishClaim(claim);error=null;changed();
  }
  Future<void> discardLocalAndPull({bool discardCanvasOutbox=false}) async {
    final result=await request('read',{'since':0});base.clear();accept(result);final raw=joinWorkspace(base);await ensureMedia(raw);
    await storage.replaceFromBackup(raw);if(discardCanvasOutbox)await storage.preferences.remove(_canvasOutbox);_lastSynced=raw;await saveBase();ready=true;error=null;changed();
  }
  Future<void> removeCleanCache() async {
    await storage.flush();if(storage.read()==_lastSynced){final raw=storage.read();await storage.clear();await storage.preferences.remove(storage.syncKey);
      if(raw!=null){final snapshot=WorkspaceSnapshot.decode(raw);for(final id in snapshot.attachmentTypes.keys){try{await MediaStorage.delete(id,owner:storage.owner);}catch(_){}await storage.preferences.remove(storage.scoped('media-sent.$id'));}}}
  }
  @override void dispose(){
    final owner = storage.owner;
    if (owner != null && identical(MediaStorage.remoteReaders[owner], _readAttachment)) {
      MediaStorage.remoteReaders.remove(owner);
    }
    memoCommentCounts.value={};_disposed=true;_networkTimer?.cancel();_canvasTimer?.cancel();storage.syncCanvas=null;storage.comments=null;storage.commentsWritable=false;storage.onChanged=null;storage.syncNow=null;storage.syncDeleted=null;storage.syncFolders=null;storage.refreshNow=null;storage.checkRemote=null;storage.watchRemote=null;storage.syncContent=null;storage.syncResource=null;storage.reloadResource=null;storage.takeLease=null;storage.inspectLease=null;storage.acquireLease=null;super.dispose();}
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  (a==null || a['deleted']==true) ? (b==null || b['deleted']==true) : b!=null && b['deleted']!=true && jsonEncode(a['value'])==jsonEncode(b['value']);

class OwnedWorkspaces {
  OwnedWorkspaces(this.root);
  final WorkspaceStorage root;
  static const claimKey='weaver.guest.claim.v1';
  static const guestOwnerKey='weaver.guest.owner.v1';
  String newGuest()=> 'guest-${List.generate(24,(_)=>Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join()}';
  WorkspaceStorage scope(String owner)=>WorkspaceStorage(root.preferences,owner:owner);
  Future<void> initialize() async {
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

class WorkspaceSync extends ChangeNotifier {
  WorkspaceSync(this.storage,this.api,{required this.isCurrent});
  final WorkspaceStorage storage;
  final EmailAuthApi api;
  final bool Function() isCurrent;
  Map<String,Map<String,dynamic>> base={};
  int cursor=0;
  String? error;
  bool busy=false,ready=false,_disposed=false;
  Timer? _timer;
  Future<void>? _running;
  String? _lastSynced;
  void changed(){if(!_disposed)notifyListeners();}
  void schedule(){changed();}
  Future<Map<String,dynamic>> request(String action,Map<String,Object?> body) async {
    if(_disposed || !isCurrent())throw const EmailAuthFailure('계정이 변경되었습니다.');
    final result=await api.workspace(action,body);
    if(_disposed || !isCurrent())throw const EmailAuthFailure('계정이 변경되었습니다.');return result;
  }
  void loadBase(){
    final raw=storage.preferences.getString(storage.syncKey);if(raw==null)return;
    final state=jsonDecode(raw) as Map;cursor=state['cursor'] as int;
    base={for(final e in (state['items'] as Map).entries)e.key as String:Map<String,dynamic>.from(e.value as Map)};
    _lastSynced=state['snapshot'] as String?;
  }
  Future<void> saveBase() async {
    if(!await storage.preferences.setString(storage.syncKey,jsonEncode({'cursor':cursor,'items':base,'snapshot':_lastSynced})))throw StateError('Sync checkpoint failed');
  }
  void accept(Map<String,dynamic> result){
    for(final raw in result['changes'] as List){final item=Map<String,dynamic>.from(raw as Map);item['value']=item['payload']==null?null:jsonDecode(item.remove('payload') as String);base[itemKey(item['kind'],item['id'])]=item;}
    cursor=result['revision'] as int;
  }
  Future<void> ensureMedia(String raw) async {
    final snapshot=WorkspaceSnapshot.decode(raw);
    for(final record in [...snapshot.records,...snapshot.trashRecords]){
      for(final id in [...record.photos.map((p)=>p.id),...record.recordings.map((p)=>p.id)]){
        if(await MediaStorage.read(id)==null){final result=await request('media/read',{'mediaId':id});await MediaStorage.write(id,base64Decode(result['data'] as String));}
      }
    }
  }
  Future<void> uploadMedia(String raw) async {
    final snapshot=WorkspaceSnapshot.decode(raw);
    for(final record in [...snapshot.records,...snapshot.trashRecords]){
      for(final id in [...record.photos.map((p)=>p.id),...record.recordings.map((p)=>p.id)]){
        final flag=storage.scoped('media-sent.$id');if(storage.preferences.getBool(flag)==true)continue;
        final bytes=await MediaStorage.read(id);if(bytes==null)throw const EmailAuthFailure('첨부파일을 읽지 못했습니다. 로컬 자료를 보존합니다.');
        await request('media/write',{'mediaId':id,'mediaType':record.recordings.any((clip)=>clip.id==id)?'audio':'image','data':base64Encode(bytes)});await storage.preferences.setBool(flag,true);
      }
    }
  }
  Future<void> initialize() async {
    loadBase();
    try {
      final current=storage.read();final local=splitWorkspace(current);
      final old=Map<String,Map<String,dynamic>>.from(base);
      final result=await request('read',{'since':cursor});accept(result);
      final merged=Map<String,Map<String,dynamic>>.from(base);
      if(current!=null && current!=_lastSynced){
        for(final key in {...old.keys,...local.keys}){
          if(!sameItem(local[key],old[key])){
            if(!sameItem(base[key],old[key]) && !sameItem(base[key],local[key]))throw const EmailAuthFailure('같은 항목의 서버 변경과 미동기화 수정이 충돌했습니다. 로컬 자료를 보관했습니다.');
            if(local[key]==null){merged.remove(key);}else{merged[key]=local[key]!;}
          }
        }
      }
      final raw=joinWorkspace(merged);await ensureMedia(raw);
      await storage.replaceFromBackup(raw,closed:true);
      if(current==null || current==_lastSynced)_lastSynced=raw;
      await saveBase();ready=true;error=null;
    }catch(e){error=e.toString();}
    storage.onChanged=schedule;storage.syncNow=flush;
    changed();if(ready && storage.read()!=_lastSynced)schedule();
  }
  Future<void> flush() async {
    await (_running??= _flush().whenComplete(()=>_running=null));
    if(error!=null)throw EmailAuthFailure(error!);
  }
  Future<void> _flush() async {
    if(_disposed || !isCurrent())return;
    _timer?.cancel();_timer=null;busy=true;changed();
    try {
      await storage.flush();
      if(!ready){await initialize();if(!ready)return;}
      final raw=storage.read();if(raw==null)return;
      final local=splitWorkspace(raw);final changes=<Map<String,dynamic>>[];
      for(final key in {...base.keys,...local.keys}){
        if(sameItem(local[key],base[key]))continue;
        final item=local[key]??base[key]!;
        changes.add({'kind':item['kind'],'id':item['id'],'value':local[key]?['value'],'deleted':!local.containsKey(key),'baseRevision':base[key]?['revision']??0});
      }
      if(changes.isNotEmpty){
        await uploadMedia(raw);
        final result=await request('save',{'since':cursor,'changes':changes});
        // Only acknowledge the submitted local snapshot. Remote-only edits are
        // fetched on the next workspace open, not applied over an active editor.
        final returned={for(final row in result['changes'] as List)itemKey(row['kind'],row['id']):row};
        for(final c in changes){final key=itemKey(c['kind'],c['id']);base[key]={...c,'revision':returned[key]?['revision']??result['revision']};}
      }
      _lastSynced=raw;await saveBase();error=null;
    }catch(e){error=e.toString();}
    finally {busy=false;changed();if(!_disposed && error==null && storage.read()!=_lastSynced)schedule();}
  }
  Future<void> importGuest(OwnedWorkspaces owned,Map<String,dynamic> claim) async {
    if(claim['account']!=storage.owner)throw const EmailAuthFailure('비회원 자료는 가져오기를 시작한 계정에만 복구할 수 있습니다.');
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
    await uploadMedia(raw);
    final result=await request('claim',{'since':0,'guestId':claim['guestId'],'sourceHash':claim['sourceHash'],'changes':changes});
    base.clear();accept(result);final combined=joinWorkspace(base);await ensureMedia(combined);
    await storage.replaceFromBackup(combined,closed:true);_lastSynced=combined;await saveBase();
    await owned.finishClaim(claim);error=null;changed();
  }
  Future<void> discardLocalAndPull() async {
    final result=await request('read',{'since':0});base.clear();accept(result);final raw=joinWorkspace(base);await ensureMedia(raw);
    await storage.replaceFromBackup(raw,closed:true);_lastSynced=raw;await saveBase();ready=true;error=null;changed();
  }
  Future<void> removeCleanCache() async {
    await storage.flush();if(storage.read()==_lastSynced){final raw=storage.read();await storage.clear();await storage.preferences.remove(storage.syncKey);
      if(raw!=null){final snapshot=WorkspaceSnapshot.decode(raw);for(final r in [...snapshot.records,...snapshot.trashRecords]){for(final id in [...r.photos.map((p)=>p.id),...r.recordings.map((c)=>c.id)]){try{await MediaStorage.delete(id);}catch(_){}await storage.preferences.remove(storage.scoped('media-sent.$id'));}}}}
  }
  @override void dispose(){_disposed=true;_timer?.cancel();storage.onChanged=null;storage.syncNow=null;super.dispose();}
}

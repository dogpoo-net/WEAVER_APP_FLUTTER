import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';

class Server extends EmailAuthApi {
  int revision=0;
  final items=<String,Map<String,dynamic>>{},leases=<String,String>{};
  final actions=<String>[];
  @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body)async{
    actions.add(action);
    if(action=='status')return {'revision':revision,'leases':{for(final e in (body['documentLeases'] as Map).entries)e.key:{'acquired':leases[e.key]==e.value}}};
    if(action=='document-lease'){
      final id=body['documentId'] as String,token=body['leaseToken'] as String;
      if(body['release']==true){if(leases[id]==token)leases.remove(id);return {'released':true};}
      if(body['takeover']!=true && ((leases[id]!=null && leases[id]!=token) || (body['renewOnly']==true && leases[id]==null)))return {'acquired':false};
      leases[id]=token;return {'acquired':true};
    }
    if(action=='save'){
      final changes=body['changes'] as List;
      for(final c in changes){final key=itemKey(c['kind'],c['id']);if((items[key]?['revision']??0)!=c['baseRevision'])throw const EmailAuthFailure('conflict');}
      revision++;
      for(final c in changes){items[itemKey(c['kind'],c['id'])]={'kind':c['kind'],'id':c['id'],'payload':c['deleted']==true?null:jsonEncode(c['value']),'deleted':c['deleted'],'revision':revision};}
      return {'revision':revision,'changes':[for(final c in changes)items[itemKey(c['kind'],c['id'])]]};
    }
    return {'revision':revision,'changes':items.values.where((i)=>i['revision']>(body['since'] as int? ?? 0)).toList()};
  }
}
Map<String,dynamic> sample()=>{'version':1,'colors':{},'elements':[{'id':'t','text':'first','createdAt':'2026-01-01T00:00:00.000','tags':[]}],'trash':[],'notes':[{'id':'n','content':'saved','createdAt':'2026-01-01T00:00:00.000','tags':[],'bindings':[],'project':{'id':'p','name':'doc','document':'saved','paragraphs':[],'words':[],'tags':[]}}],'graphLayout':{'positions':{'t':[10,20]},'blocks':{'positions':{'t':[30,40]}}}};
void main(){
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('two devices receive create update delete deltas; status never sends full data',()async{
    final prefs=await SharedPreferences.getInstance(),server=Server();
    final a=WorkspaceSync(WorkspaceStorage(prefs,owner:'a'),server,isCurrent:()=>true),b=WorkspaceSync(WorkspaceStorage(prefs,owner:'b'),server,isCurrent:()=>true);
    await a.initialize();await b.initialize();await a.storage.write(jsonEncode(sample()));await a.flush();
    expect(await b.checkRemote(),true);await b.refreshFromServer();expect(b.storage.read(),contains('first'));expect(await b.checkRemote(),false);
    final edit=sample();edit['elements'][0]['text']='updated';edit['notes'][0]['project']['document']='unsaved';edit['graphLayout']['positions']['t']=[99,99];
    await a.storage.write(jsonEncode(edit));await a.storage.syncContent!();await b.refreshFromServer();
    final received=jsonDecode(b.storage.read()!);expect(received['elements'][0]['text'],'updated');expect(received['notes'][0]['project']['document'],'saved');expect(received['graphLayout']['positions']['t'],[10,20]);
    edit['elements']=[];await a.storage.write(jsonEncode(edit));await a.flushDeletions();await b.refreshFromServer();expect(jsonDecode(b.storage.read()!)['elements'],isEmpty);
    a.dispose();b.dispose();server.dispose();
  });
  test('takeover rebases only confirmed scope, retains local draft and refresh discards only that scope',()async{
    final prefs=await SharedPreferences.getInstance(),server=Server();final a=WorkspaceSync(WorkspaceStorage(prefs,owner:'a'),server,isCurrent:()=>true),b=WorkspaceSync(WorkspaceStorage(prefs,owner:'b'),server,isCurrent:()=>true);
    await a.initialize();await a.storage.write(jsonEncode(sample()));await a.flush();await b.initialize();
    final tokenA='a'*64,tokenB='b'*64;
    await a.documentLease('canvas:diagram',tokenA,false);expect((await b.documentLease('canvas:diagram',tokenB,false))['acquired'],false);
    final edit=sample();edit['graphLayout']['positions']['t']=[100,200];await a.storage.write(jsonEncode(edit));await a.storage.syncResource!('canvas:diagram');
    final own=sample();own['graphLayout']['positions']['t']=[70,80];own['notes'][0]['project']['document']='private draft';await b.storage.write(jsonEncode(own));
    await b.takeLease('canvas:diagram',tokenB);expect(b.storage.read(),contains('private draft'));expect(jsonDecode(b.storage.read()!)['graphLayout']['positions']['t'],[70,80]);
    await a.checkRemote();expect(a.documentLeases.containsKey('canvas:diagram'),false);expect((await a.documentLease('canvas:diagram',tokenA,false))['acquired'],false);
    await b.storage.syncResource!('canvas:diagram');expect(jsonDecode(server.items[itemKey('layout','["page","positions","t"]')]!['payload']),[70,80]);
    own['graphLayout']['positions']['t']=[8,9];await b.storage.write(jsonEncode(own));await b.reloadResource('canvas:diagram');expect(jsonDecode(b.storage.read()!)['graphLayout']['positions']['t'],[70,80]);expect(b.storage.read(),contains('private draft'));
    a.dispose();b.dispose();server.dispose();
  });
  test('JSON key order and numeric representation do not create false conflicts',(){
    expect(sameItem({'value':{'a':1,'b':[2.0]}},{'value':{'b':[2],'a':1.0}}),true);
  });
}

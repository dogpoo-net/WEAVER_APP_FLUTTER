import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_comments.dart';
import 'package:weaver/features/inbox/memo_comment_count.dart';
import 'package:weaver/features/inbox/thought_label.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'owned_workspace_test.dart' show DeltaApi;

class CountingApi extends DeltaApi {
  final counts=<String,int>{};
  Completer<void>? release;
  @override Future<Map<String,dynamic>> workspace(String action,Map<String,Object?> body) async {
    counts.update(action,(n)=>n+1,ifAbsent:()=>1);
    if(release!=null) await release!.future;
    return super.workspace(action,body);
  }
}
void main(){
  test('ID index follows restore, rename, replacement, delete and workspace reset',(){
    final store=ElementStore();addTearDown(store.dispose);
    final a=store.add('first');expect(store.byId(a.id),same(a));
    store.update('first','renamed');expect(store.byId(a.id)?.text,'renamed');
    final b=ElementRecord('replacement');store.records['renamed']=b;
    expect(store.byId(a.id),isNull);expect(store.byId(b.id),same(b));
    store.remove('renamed');expect(store.byId(b.id),isNull);
    store.records.addAll({'restored':a});expect(store.byId(a.id),same(a));
    store.clear();expect(store.byId(a.id),isNull);
  });
  testWidgets('one comment change rebuilds only its own badge',(tester)async{
    memoCommentCounts.value={};final builds=List.filled(1000,0);
    await tester.pumpWidget(MaterialApp(home:Stack(children:[for(var i=0;i<1000;i++)
      MemoCommentCount(id:'$i',builder:(context,count){builds[i]++;return const SizedBox();})])));
    final before=List.of(builds);
    memoCommentCounts.value={'42':1};await tester.pump();
    expect(builds[42],before[42]+1);
    for(var i=0;i<1000;i++){if(i!=42)expect(builds[i],before[i]);}
    memoCommentCounts.value={};await tester.pump();expect(builds[42],before[42]+2);
    await tester.pumpWidget(const SizedBox());memoCommentCounts.value={};
  });
  testWidgets('label cache follows text scale and content',(tester)async{
    Future<double> measure(String text,double scale)async{
      late double width;
      await tester.pumpWidget(Directionality(textDirection:TextDirection.ltr,child:MediaQuery(data:MediaQueryData(textScaler:TextScaler.linear(scale)),child:Builder(builder:(context){width=ThoughtLabel.width(context,text);return const SizedBox();}))));
      return width;
    }
    final original=await measure('label',1);
    expect(await measure('label',2),greaterThan(original));
    expect(await measure('longer label',1),greaterThan(original));
    expect(await measure('label',1),original);
  });
  test('concurrent reads and status checks share one request, later checks still run',()async{
    SharedPreferences.setMockInitialValues({});
    final api=CountingApi();final storage=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'performance');
    final sync=WorkspaceSync(storage,api,isCurrent:()=>true);
    addTearDown((){sync.dispose();api.dispose();});
    await sync.initialize();api.counts.clear();
    api.release=Completer<void>();
    final readers=[for(var i=0;i<10;i++)sync.refreshFromServer()];
    api.release!.complete();await Future.wait(readers);api.release=null;
    expect(api.counts['read'],1);
    api.release=Completer<void>();
    final checks=[for(var i=0;i<10;i++)sync.checkRemote()];
    api.release!.complete();await Future.wait(checks);api.release=null;
    expect(api.counts['status'],1);
    await sync.checkRemote();expect(api.counts['status'],2);
    await sync.refreshFromServer();expect(api.counts['read'],2);
  });
}

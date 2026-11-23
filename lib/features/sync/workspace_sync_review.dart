import 'startup_recovery.dart';
import 'network_recovery.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../inbox/workspace_storage.dart';
import 'owned_workspace.dart';
import 'offline_workspace.dart';

class SyncDifference {
  SyncDifference(this.id,this.title);
  final String id,title;
  final keys=<String>[];
}
List<SyncDifference> syncDifferences(Map<String,Map<String,dynamic>> local,Map<String,Map<String,dynamic>> remote){
  final groups=<String,SyncDifference>{};
  for(final key in {...local.keys,...remote.keys}){
    final item=local[key]??remote[key]!;
    if(item['kind']=='layout'||item['kind']=='list:memoBoxes'||sameItem(local[key],remote[key]))continue;
    final kind=item['kind'] as String,id=item['id'] as String;
    String group=key,title;
    if(kind=='layout'){
      final path=List<String>.from(jsonDecode(id));
      final object=path.length>2?path.last:'배치 설정';
      group='layout:${path.first}:$object';
      final memo=local[itemKey('list:elements',object)]??remote[itemKey('list:elements',object)];
      final value=memo?['value'];
      final label=value is Map?value['text']?.toString():null;
      title='배치 · ${label??(object=='배치 설정'?object:'개체')} · ${path.first.startsWith('box:')?path.first.substring(4):'캔버스'}';
    }else{
      final value=item['value'];
      final text=value is Map?(value['text']??value['content']??value['name']??value['title']):value;
      title='${switch(kind){'list:elements'=>'생각','list:notes'=>'문서·메모','list:memoBoxes'=>'메모상자','list:trash'=>'휴지통',_=>'분류·설정'}}${text==null?'':' · $text'}';
    }
    groups.putIfAbsent(group,()=>SyncDifference(group,title)).keys.add(key);
  }
  return groups.values.toList();
}
List<Map<String,dynamic>> reviewChanges(List<SyncDifference> differences,Map<String,bool> choices,Map<String,Map<String,dynamic>> local,Map<String,Map<String,dynamic>> remote){
  if(differences.any((d)=>!choices.containsKey(d.id)))throw StateError('각 항목의 처리 방법을 선택해주세요.');
  return [for(final group in differences)if(choices[group.id]==true)for(final key in group.keys){
    ...(local[key]??remote[key]!),
    'deleted':local[key]==null||local[key]?['deleted']==true,
    'baseRevision':remote[key]?['revision']??0,
    if((local[key]??remote[key])?['kind']=='list:memoBoxes')'previousValue':remote[key]?['value'],
  }];
}
class WorkspaceSyncReviewPage extends StatefulWidget {
  const WorkspaceSyncReviewPage({super.key,required this.engine,required this.source,this.startupRecovery=false});
  final WorkspaceSync engine;
  final WorkspaceStorage source;
  final bool startupRecovery;
  @override State<WorkspaceSyncReviewPage> createState()=>_WorkspaceSyncReviewPageState();
}
class _WorkspaceSyncReviewPageState extends State<WorkspaceSyncReviewPage>{
  bool busy=true,loaded=false,applying=false;String? error;int revision=0;
  Map<String,Map<String,dynamic>> local={},remote={};
  List<Map<String,dynamic>> automatic=[];
  List<SyncDifference> differences=[];final choices=<String,bool>{};
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    setState((){busy=true;error=null;});
    try{
      await widget.source.flush();
      if (!mounted) return;
      if(!widget.startupRecovery)await OfflineWorkspace.preserveRecovery(widget.source,widget.engine.storage);
      if (!mounted) return;
      final result=await widget.engine.request('read',{'since':0});
      if (!mounted) return;
      final next=<String,Map<String,dynamic>>{};
      for(final raw in result['changes'] as List){final item=Map<String,dynamic>.from(raw);item['value']=item['payload']==null?null:jsonDecode(item['payload']);next[itemKey(item['kind'],item['id'])]=item;}
      if(!mounted)return;
      local=splitWorkspace(widget.source.read());remote=next;revision=result['revision'] as int;
      choices.clear(); automatic=[];
      if(widget.startupRecovery){
        final pending=startupRecoveryItems(widget.source);
        local=Map.of(remote);
        for(final entry in pending.entries){local[entry.key]=entry.value;}
        differences=syncDifferences(local,remote);
        final pruned={for(final item in pending.entries)if(!sameItem(item.value,remote[item.key]))item.key:item.value};
        if(!await widget.source.preferences.setString(startupRecoveryKey(widget.source),jsonEncode(pruned)))throw StateError('복구 목록을 저장하지 못했습니다.');
      }else if(widget.engine.networkPending || widget.source.owner != widget.engine.storage.owner){
        final baseline = widget.source.owner == widget.engine.storage.owner
            ? widget.engine.recoveryBase
            : splitWorkspace(widget.source.preferences.getString(OfflineWorkspace.baseline(widget.source)) ??
                (throw StateError('오프라인 비교 기준이 없습니다.')));
        final plan=NetworkRecoveryPlan(baseline,local,remote);
        local=plan.merged;automatic=plan.automatic;
        differences=syncDifferences(local,remote).where((d)=>d.keys.any(plan.conflicts.contains)).toList();
      }else{differences=syncDifferences(local,remote);}
      loaded=true;
    }catch(e){if(mounted)error=e.toString();}finally{if(mounted)setState(()=>busy=false);}
  }
  String preview(SyncDifference difference,Map<String,Map<String,dynamic>> items){
    final lines=<String>[];
    for(final key in difference.keys){
      final item=items[key];if(item==null||item['deleted']==true){lines.add('없음 (삭제)');continue;}
      final value=item['value'];
      if(item['kind']=='layout'){
        final path=List<String>.from(jsonDecode(item['id']));
        final field=path.length>1?path[path.length-2]:path.last;
        final label=switch(field){'positions'=>'위치','sizes'=>'크기','tags'=>'해시태그 위치','folderPositions'=>'폴더 위치','stackGroups'=>'겹침 그룹',_=>'배치 설정'};
        lines.add('$label: ${value is List?value.join(', '):value}');
      }else if(value is Map){
        final project=value['project'];
        final text=project is Map?project['document']:value['text']??value['content']??value['name'];
        lines.add('${text??'자료 있음'}');
        if(value['ids'] is List){
          final names=[for(final id in value['ids'] as List)(items[itemKey('list:elements',id)]?['value'] as Map?)?['text']??'생각'];
          lines.add('포함된 생각 ${names.length}개: ${names.join(', ')}');
        }
        if(value['photos'] is List)lines.add('사진 ${(value['photos'] as List).length}개');
        if(value['recordings'] is List)lines.add('음성 ${(value['recordings'] as List).length}개');
      }else{lines.add('$value');}
    }
    return lines.join('\n');
  }
  Future<void> apply()async{
    final changes=[...automatic,...reviewChanges(differences,choices,local,remote)];
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('선택한 내용으로 동기화할까요?'),content:const Text('로컬을 선택한 항목은 서버 내용을 덮어쓰며 다른 참여자에게도 반영됩니다. 로컬에 없는 항목은 서버에서도 삭제됩니다. 서버를 선택한 항목의 로컬 변경은 버립니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('적용'))]));
    if(yes!=true||!mounted)return;
    setState((){busy=true;applying=true;error=null;});
    try{
      final check=await widget.engine.request('read',{'since':0});
      if(check['revision']!=revision)throw StateError('비교 후 서버 자료가 바뀌었습니다. 다시 비교한 뒤 선택해주세요. 아직 반영하지 않았습니다.');
      if(changes.isNotEmpty){
        // Only chosen content can require attachment uploads.
        final chosen={for(final c in changes)if(c['deleted']!=true)itemKey(c['kind'],c['id']):c};
        await widget.engine.uploadMedia(joinWorkspace(chosen),sourceOwner:widget.source.owner);
        await widget.engine.request('save',{'since':revision,'changes':changes,'offlineReconcile':true});
      }
      await widget.engine.discardLocalAndPull(discardCanvasOutbox:true);
      if(widget.startupRecovery){
        if(!await widget.source.preferences.setString(startupRecoveryKey(widget.source),'{}'))throw StateError('복구 목록을 지우지 못했습니다.');
      }else if(widget.source.owner!=widget.engine.storage.owner){
        final raw=widget.engine.storage.read()!;
        await OfflineWorkspace.copyMedia(raw,widget.engine.storage.owner,widget.source.owner);
        await widget.source.replaceFromBackup(raw);
        await widget.source.preferences.setString(OfflineWorkspace.baseline(widget.source),raw);
      }
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error=e.toString());}finally{if(mounted)setState((){busy=false;applying=false;});}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!applying,child:Scaffold(
    appBar:AppBar(title:const Text('동기화'),actions:[IconButton(tooltip:'다시 비교',onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),
    body:CustomScrollView(slivers:[SliverPadding(padding:const EdgeInsets.all(16),sliver:SliverMainAxisGroup(slivers:[
      SliverList.list(children:[
      const Text('항목마다 남길 내용을 선택하세요. 선택 전에는 자료를 변경하지 않습니다.'),
      if(widget.source.owner!=widget.engine.storage.owner)const Text('보관된 오프라인 자료와 현재 서버 자료를 비교합니다.'),
      if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(loaded&&differences.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('서로 다른 자료가 없습니다.')),
      ]),
      SliverList.builder(itemCount:differences.length,itemBuilder:(context,index){
        final d=differences[index];
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(d.title,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleSmall),
        const SizedBox(height:8),const Text('로컬'),ConstrainedBox(constraints:const BoxConstraints(maxHeight:180),child:SingleChildScrollView(child:SelectableText(preview(d,local)))),
        const Divider(),const Text('서버'),ConstrainedBox(constraints:const BoxConstraints(maxHeight:180),child:SingleChildScrollView(child:SelectableText(preview(d,remote)))),
        Wrap(spacing:8,children:[ChoiceChip(label:const Text('로컬로 서버 덮어쓰기'),selected:choices[d.id]==true,onSelected:busy?null:(_)=>setState(()=>choices[d.id]=true)),ChoiceChip(label:const Text('로컬 변경 버리고 서버 사용'),selected:choices[d.id]==false,onSelected:busy?null:(_)=>setState(()=>choices[d.id]=false))]),
      ])));
      }),
      SliverList.list(children:[
      if(differences.isNotEmpty || automatic.isNotEmpty)FilledButton(onPressed:busy||choices.length!=differences.length?null:apply,child:const Text('선택한 내용 적용')),
      ]),
    ]))]),
  ));
}

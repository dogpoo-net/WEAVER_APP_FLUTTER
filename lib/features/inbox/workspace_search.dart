import 'overview_tab_activity.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'desktop_menu_frame.dart';
import 'element_store.dart';
import 'overview_collections.dart';
import 'project_page.dart';
import 'thought_settings.dart';
import 'workspace_storage.dart';
import 'workspace_routes.dart';

class WorkspaceSearchResult {
  const WorkspaceSearchResult(this.kind, this.title, this.body, {this.note, this.record, this.audioId});
  final String kind, title, body;
  final Note? note;
  final ElementRecord? record;
  final String? audioId;
  DateTime get date => note?.updatedAt ?? note?.createdAt ?? record!.createdAt;
  String get key => '$kind-${note?.id ?? audioId ?? record!.id}';
}
List<WorkspaceSearchResult> searchWorkspace(List<Note> notes, Iterable<ElementRecord> records, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  bool matches(String text) { final lower = text.toLowerCase(); return words.every(lower.contains); }
  return [
    for (final n in notes)
      if (n.project != null && matches('${n.project!.title}\n${n.project!.content}'))
        WorkspaceSearchResult('문서', n.project!.title, n.project!.content, note:n),
    for (final r in records.where((r)=>r.deletedAt == null && canBrowseThought(r))) ...[
      if (matches('${r.indexLabel}\n${r.text}\n${r.tags.join(' ')}'))
        WorkspaceSearchResult('생각', r.indexLabel.isEmpty ? r.text : r.indexLabel, r.text, record:r),
      for (final voice in r.recordings)
        if (voice.transcript.trim().isNotEmpty && matches(voice.transcript))
          WorkspaceSearchResult('음성', r.title, voice.transcript, record:r, audioId:voice.id),
    ],
  ]..sort((a,b){final order=b.date.compareTo(a.date);return order!=0?order:a.key.compareTo(b.key);});
}
class WorkspaceSearch extends StatefulWidget {
  const WorkspaceSearch({super.key, required this.notes, required this.selector, required this.controller, this.onDocument});
  final List<Note> notes;
  final Widget selector;
  final TextEditingController controller;
  final Future<void> Function(Note)? onDocument;
  @override State<WorkspaceSearch> createState()=>_WorkspaceSearchState();
}
class _WorkspaceSearchState extends State<WorkspaceSearch> with RetainedOverviewTab<WorkspaceSearch> {
  Timer? _debounce;
  late String _query = widget.controller.text;
  final _scroll = ScrollController();
  int _limit = 20;
  List<WorkspaceSearchResult>? _results;
  void _refresh(){_results=null;if(mounted && tabActive)setState((){});}
  void _loadMore(){
    if(_scroll.hasClients && _scroll.position.extentAfter < 200 && _limit < (_results?.length ?? 0)) {
      setState(()=>_limit=math.min(_limit+20,_results!.length));
    }
  }
  void _search(String value){
    if(!mounted)return;
    if(_scroll.hasClients)_scroll.jumpTo(0);
    setState((){_query=value;_limit=20;_results=null;});
  }
  @override void didUpdateWidget(covariant WorkspaceSearch oldWidget){
    super.didUpdateWidget(oldWidget);_results=null;
  }
  @override void initState(){super.initState();elements.addListener(_refresh);_scroll.addListener(_loadMore);}
  @override void dispose(){_debounce?.cancel();elements.removeListener(_refresh);_scroll.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final results=_results??=searchWorkspace(widget.notes,elements.records.values,_query);
    return Scaffold(appBar:AppBar(centerTitle:false,titleSpacing:0,leadingWidth:44,title:const WorkspaceTitle('전체 보기'),actions:const[DesktopMenuAction()]),
      body:DesktopMenuBody(child:Column(children:[widget.selector,
        Padding(padding:const EdgeInsets.fromLTRB(12,4,12,0),child:TextField(key:const ValueKey('workspace-search'),controller:widget.controller,
          style:TextStyle(fontSize:MediaQuery.sizeOf(context).width<1000?13:14),
          decoration:const InputDecoration(hintText:'자료 검색',prefixIcon:Icon(Icons.search,size:18),prefixIconConstraints:BoxConstraints(minWidth:36,minHeight:36),contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8),isDense:true),
          onChanged:(value){_debounce?.cancel();_debounce=Timer(const Duration(milliseconds:200),()=>_search(value));})),
        if(_query.trim().isNotEmpty)Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Align(alignment:Alignment.centerLeft,child:Text('검색 결과 ${results.length}개'))),
        Expanded(child:results.isEmpty?Center(child:Text(_query.trim().isEmpty?'아직 자료가 없습니다.':'일치하는 자료가 없습니다.')):
          ListView.separated(key:const ValueKey('workspace-search-results'),controller:_scroll,itemCount:math.min(_limit,results.length),padding:const EdgeInsets.all(12),separatorBuilder:(_,i)=>const Divider(height:1),itemBuilder:(context,i){
            final item=results[i];
            final body=excerpt(item.body);
            final at=body.toLowerCase().indexOf(_query.trim().toLowerCase());
            final preview=at>60?'…${body.substring(at-40)}':body;
            return ListTile(key:ValueKey('search-${item.kind}-${item.note?.id??item.audioId??item.record!.id}'),
              leading:Icon(item.kind=='문서'?Icons.description_outlined:item.kind=='음성'?Icons.mic_none:Icons.sticky_note_2_outlined),
              title:Text('${item.kind}: ${item.title}',maxLines:1,overflow:TextOverflow.ellipsis),
              subtitle:Text(preview,maxLines:3,overflow:TextOverflow.ellipsis),
              onTap:()async{if(item.note!=null){if(widget.onDocument!=null){await widget.onDocument!(item.note!);}else{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProjectPage(project:item.note!.project!)));}}else{await showElementMetadata(context,item.record!.text);} _refresh();});
          })),
      ])));
  }
}

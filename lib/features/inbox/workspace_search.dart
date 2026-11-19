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
  static const _pageSize = 20;
  int _limit = _pageSize;
  bool _appendScheduled = false;
  List<WorkspaceSearchResult>? _results;
  int? _totalCount;
  void _refresh(){_results=null;_totalCount=null;if(mounted && tabActive)setState((){});}
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !tabActive || _appendScheduled) return false;
    final delta = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) => scrollDelta ?? 0,
      OverscrollNotification(:final overscroll) => overscroll,
      _ => 0,
    };
    if (delta <= 0 || notification.metrics.extentAfter > 1 ||
        _limit >= (_results?.length ?? 0)) return false;

    _appendScheduled = true;
    final query = _query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appendScheduled = false;
      if (!mounted || !tabActive || query != _query || !_scroll.hasClients) return;
      final count = _results?.length ?? 0;
      if (_limit < count && _scroll.position.extentAfter <= 1) {
        setState(() => _limit = math.min(_limit + _pageSize, count));
      }
    });
    return false;
  }
  void _search(String value){
    if(!mounted)return;
    if(_scroll.hasClients)_scroll.jumpTo(0);
    setState((){_query=value;_limit=_pageSize;_results=null;});
  }
  @override void didUpdateWidget(covariant WorkspaceSearch oldWidget){
    super.didUpdateWidget(oldWidget);_results=null;_totalCount=null;
  }
  @override void initState(){super.initState();elements.addListener(_refresh);}
  @override void dispose(){_debounce?.cancel();elements.removeListener(_refresh);_scroll.dispose();super.dispose();}
  int _countSearchableItems() {
    var count = widget.notes.where((note) => note.project != null).length;
    for (final record in elements.records.values) {
      if (record.deletedAt != null || !canBrowseThought(record)) continue;
      count += 1 + record.recordings.where((voice) => voice.transcript.trim().isNotEmpty).length;
    }
    return count;
  }
  @override Widget build(BuildContext context){
    final results=_results??=searchWorkspace(widget.notes,elements.records.values,_query);
    final hasQuery = _query.trim().isNotEmpty;
    final total = _totalCount ??= hasQuery ? _countSearchableItems() : results.length;
    return Scaffold(appBar:AppBar(centerTitle:false,titleSpacing:0,leadingWidth:44,title:const WorkspaceTitle('전체 보기'),actions:const[DesktopMenuAction()]),
      body:DesktopMenuBody(child:Column(children:[widget.selector,
        Padding(padding:const EdgeInsets.fromLTRB(12,4,12,0),child:TextField(key:const ValueKey('workspace-search'),controller:widget.controller,
          style:TextStyle(fontSize:MediaQuery.sizeOf(context).width<1000?13:14),
          decoration:const InputDecoration(hintText:'자료 검색',prefixIcon:Icon(Icons.search,size:18),prefixIconConstraints:BoxConstraints(minWidth:36,minHeight:36),contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8),isDense:true),
          onChanged:(value){_debounce?.cancel();_debounce=Timer(const Duration(milliseconds:200),()=>_search(value));})),
        OverviewItemCount(hasQuery
          ? '검색 결과 ${results.length}개 / 전체 ${total}개'
          : '자료 ${total}개'),
        Expanded(child:results.isEmpty?Center(child:Text(_query.trim().isEmpty?'아직 자료가 없습니다.':'일치하는 자료가 없습니다.')):
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              key: const ValueKey('workspace-search-results'),controller:_scroll,itemCount:math.min(_limit,results.length),padding:const EdgeInsets.fromLTRB(12,8,12,12),separatorBuilder:(_,i)=>const Divider(height:1),itemBuilder:(context,i){
            final item=results[i];
            final body=excerpt(item.body);
            final at=body.toLowerCase().indexOf(_query.trim().toLowerCase());
            final preview=at>60?'…${body.substring(at-40)}':body;
            return ListTile(key:ValueKey('search-${item.kind}-${item.note?.id??item.audioId??item.record!.id}'),
              leading:Icon(item.kind=='문서'?Icons.description_outlined:item.kind=='음성'?Icons.mic_none:Icons.sticky_note_2_outlined),
              title:Text('${item.kind}: ${item.title}',maxLines:1,overflow:TextOverflow.ellipsis),
              subtitle:Text(preview,maxLines:3,overflow:TextOverflow.ellipsis),
              onTap:()async{if(item.note!=null){if(widget.onDocument!=null){await widget.onDocument!(item.note!);}else{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProjectPage(project:item.note!.project!)));}}else{await showElementMetadata(context,item.record!.text);} _refresh();});
          }))),
      ])));
  }
}

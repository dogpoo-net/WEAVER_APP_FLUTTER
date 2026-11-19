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
  const WorkspaceSearchResult(this.kind, this.title, this.body, {this.note, this.record});
  final String kind, title, body;
  final Note? note;
  final ElementRecord? record;
  DateTime get date => note?.updatedAt ?? note?.createdAt ?? record!.createdAt;
  String get key => '$kind-${note?.id ?? record!.id}';
}

Iterable<String> _searchTerms(String query) =>
    query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);

bool _searchableThought(ElementRecord record) =>
    record.deletedAt == null && canBrowseThought(record);

List<WorkspaceSearchResult> searchWorkspace(
  List<Note> notes,
  Iterable<ElementRecord> records,
  String query,
) {
  final words = _searchTerms(query).toList();
  bool matches(String text) {
    if (words.isEmpty) return true;
    final lower = text.toLowerCase();
    return words.every(lower.contains);
  }

  final results = [
    for (final note in notes)
      if (note.project case final project?)
        if (matches('${project.title}\n${project.content}'))
          WorkspaceSearchResult('문서', project.title, project.content, note: note),
  ];
  for (final record in records.where(_searchableThought)) {
    final title = record.indexLabel.isEmpty ? record.text : record.indexLabel;
    final tags = record.tags.map((tag) => '#$tag').join(' ');
    final bodyMatches = words.isEmpty || matches('$title\n${record.text}\n$tags');
    final transcript = words.isEmpty ? null : record.recordings
        .map((voice) => voice.transcript)
        .where((text) => text.trim().isNotEmpty && matches(text))
        .firstOrNull;
    if (!bodyMatches && transcript == null) continue;
    final preview = matches(record.text)
        ? record.text
        : transcript ?? (matches(tags) ? tags : record.text);
    results.add(WorkspaceSearchResult('생각', title, preview, record: record));
  }
  return results..sort((a, b) {
    final order = b.date.compareTo(a.date);
    return order != 0 ? order : a.key.compareTo(b.key);
  });
}

Widget _highlightedSearchText(BuildContext context, String text, RegExp? pattern, int maxLines, {String prefix = ''}) {
  final spans = <InlineSpan>[];
  var offset = 0;
  final colors = Theme.of(context).colorScheme;
  final highlight = TextStyle(
    backgroundColor: colors.tertiaryContainer,
    color: colors.onTertiaryContainer,
  );
  if (pattern != null) {
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(TextSpan(text: match.group(0), style: highlight));
      offset = match.end;
    }
  }
  if (spans.isEmpty) return Text('$prefix$text', maxLines: maxLines, overflow: TextOverflow.ellipsis);
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return Text.rich(TextSpan(children: [if (prefix.isNotEmpty) TextSpan(text: prefix), ...spans]), maxLines: maxLines, overflow: TextOverflow.ellipsis);
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
  int _countSearchableItems() =>
      widget.notes.where((note) => note.project != null).length +
      elements.records.values.where(_searchableThought).length;
  @override Widget build(BuildContext context){
    final results=_results??=searchWorkspace(widget.notes,elements.records.values,_query);
    final terms = _searchTerms(_query).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final hasQuery = terms.isNotEmpty;
    final pattern = hasQuery
        ? RegExp(terms.map(RegExp.escape).join('|'), caseSensitive: false, unicode: true)
        : null;
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
            final match = pattern?.firstMatch(body);
            var start = math.max(0, (match?.start ?? 0) - 24);
            if (start > 0 && (body.codeUnitAt(start) & 0xFC00) == 0xDC00) start--;
            final preview = start == 0 ? body : '…${body.substring(start)}';
            return ListTile(
              key: ValueKey('search-${item.key}'),
              leading: Icon(item.kind == '문서' ? Icons.description_outlined : Icons.sticky_note_2_outlined),
              title: _highlightedSearchText(context, item.title, pattern, 1, prefix: '${item.kind}: '),
              subtitle: _highlightedSearchText(context, preview, pattern, 3),
              onTap:()async{if(item.note!=null){if(widget.onDocument!=null){await widget.onDocument!(item.note!);}else{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProjectPage(project:item.note!.project!)));}}else{await showElementMetadata(context,item.record!.text);} _refresh();});
          }))),
      ])));
  }
}

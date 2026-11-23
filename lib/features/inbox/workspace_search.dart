import 'memo_boxes.dart';
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
  const WorkspaceSearchResult(this.kind, this.title, this.body, {this.note, this.record, this.box, this.voiceId, this.boxDate});
  final String kind, title, body;
  final Note? note;
  final ElementRecord? record;
  final MemoBox? box;
  final String? voiceId;
  final DateTime? boxDate;
  DateTime? get date => note?.updatedAt ?? note?.createdAt ?? record?.createdAt ?? boxDate;
  String get key => voiceId == null
      ? '$kind-${note?.id ?? record?.id ?? box!.name}'
      : '$kind-${record!.id}-$voiceId';
}

Iterable<String> _searchTerms(String query) =>
    query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);

bool _searchableThought(ElementRecord record) =>
    record.deletedAt == null && canBrowseThought(record);

List<WorkspaceSearchResult> searchWorkspace(
  List<Note> notes,
  Iterable<ElementRecord> records,
  String query, {bool includeExtra = false}
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
        if (matches('${project.title}\n${project.content}\n${project.tags.map((tag) => '#$tag').join(' ')}'))
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
    if (includeExtra) {
      for (final voice in record.recordings) {
        if (voice.transcript.trim().isNotEmpty && matches('$title\n$tags\n${voice.transcript}')) {
          results.add(WorkspaceSearchResult('음성텍스트', title, voice.transcript,
            record: record, voiceId: voice.id));
        }
      }
    }
    if (!bodyMatches && (includeExtra || transcript == null)) continue;
    final preview = matches(record.text)
        ? record.text
        : transcript ?? (matches(tags) ? tags : record.text);
    results.add(WorkspaceSearchResult('생각', title, preview, record: record));
  }
  if (includeExtra) {
    final active = {for (final record in records.where(_searchableThought)) record.id: record};
    for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
      final path = memoBoxPath(box);
      if (!matches(path)) continue;
      DateTime? latest;
      for (final id in memoBoxContents(box, includeChildren: true)) {
        final date = active[id]?.createdAt;
        if (date != null && (latest == null || date.isAfter(latest))) latest = date;
      }
      results.add(WorkspaceSearchResult('메모상자', box.name, path, box: box, boxDate: latest));
    }
  }
  return results..sort((a, b) {
    final aDate = a.date, bDate = b.date;
    final order = aDate == null ? (bDate == null ? 0 : 1)
        : bDate == null ? -1 : bDate.compareTo(aDate);
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
  const WorkspaceSearch({super.key, required this.notes, required this.selector, required this.controller, this.onDocument, this.onBox});
  final List<Note> notes;
  final Widget selector;
  final TextEditingController controller;
  final Future<void> Function(Note)? onDocument;
  final ValueChanged<MemoBox>? onBox;
  @override State<WorkspaceSearch> createState()=>_WorkspaceSearchState();
}
enum _SearchDate {
  day('1일 전', days: 1), threeDays('3일 전', days: 3),
  week('1주일 전', days: 7), month('1달 전', months: 1),
  threeMonths('3달 전', months: 3), sixMonths('6달 전', months: 6),
  year('1년 전', months: 12), threeYears('3년 전', months: 36),
  fiveYears('5년 전', months: 60), all('전체');

  const _SearchDate(this.label, {this.days = 0, this.months = 0});
  final String label;
  final int days, months;

  DateTime? cutoff(DateTime now) {
    if (this == all) return null;
    if (days != 0) return DateTime(now.year, now.month, now.day - days);
    final month = DateTime(now.year, now.month - months);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(now.day, lastDay));
  }
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
  static const _types = ['생각', '문서', '메모상자', '음성텍스트'];
  final _selectedTypes = _types.toSet();
  String? _tag, _attachment;
  MemoBox? _box;
  _SearchDate _date = _SearchDate.all;
  bool _descendants = true;
  bool get _filtered =>
      _selectedTypes.length != _types.length || _tag != null || _attachment != null || _box != null || _date != _SearchDate.all;

  List<WorkspaceSearchResult> _filterResults(List<WorkspaceSearchResult> results) {
    final ids = _box == null ? null : memoBoxContents(_box!, includeChildren: _descendants);
    final cutoff = _date.cutoff(DateTime.now());
    return results.where((item) {
      final record = item.record;
      final tags = record?.tags ?? item.note?.project?.tags ?? <String>{};
      return _selectedTypes.contains(item.kind) &&
          (ids == null || ids.contains(record?.id) ||
            (item.box != null && (_descendants ? memoBoxContains(_box!, item.box!) : item.box == _box))) &&
          (_tag == null || tags.contains(_tag)) &&
          (cutoff == null || (item.date != null && !item.date!.isBefore(cutoff))) &&
          switch (_attachment) {
            '사진' => record?.photos.isNotEmpty == true,
            '음성' => record?.recordings.isNotEmpty == true,
            '위치' => record?.location != null,
            _ => true,
          };
    }).toList();
  }

  void _changeFilter(VoidCallback update) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      update();
      _limit = _pageSize;
      _results = null;
    });
  }

  Widget _filterMenu<T extends Object>(
    String label, T? value, Iterable<T> values, String Function(T) title,
    ValueChanged<T?> change,
  ) => PopupMenuButton<T>(
    tooltip: label,
    onSelected: (value) => _changeFilter(() => change(value)),
    itemBuilder: (_) => [
      for (final option in values) PopupMenuItem(value: option, child: Text(title(option))),
    ],
    child: InputChip(
      label: Text(value == null ? label : title(value)),
      onDeleted: value == null ? null : () => _changeFilter(() => change(null)),
    ),
  );

  Widget _filters() {
    final tags = {
      ...elements.records.values.where(_searchableThought).expand((record) => record.tags),
      ...widget.notes.expand((note) => note.project?.tags ?? <String>{}),
    }.toList()..sort();
    return Drawer(
      width: 320,
      child: SafeArea(child: StatefulBuilder(builder: (context, updateDrawer) {
        void update(VoidCallback change) {
          _changeFilter(change);
          updateDrawer(() {});
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(children: [
              const Expanded(child: Text('검색 필터')),
              if (_filtered) TextButton(onPressed: () => update(() {
                _selectedTypes..clear()..addAll(_types);
                _tag = _attachment = null;
                _box = null;
                _date = _SearchDate.all;
                _descendants = true;
              }), child: const Text('초기화')),
              IconButton(tooltip: '필터 닫기', onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
            ]),
            const ListTile(dense: true, title: Text('유형')),
              for (final type in _types)
                CheckboxListTile(
                  dense: true, title: Text(type), value: _selectedTypes.contains(type),
                  onChanged: (checked) => update(() {
                    if (checked == true) _selectedTypes.add(type);
                    else _selectedTypes.remove(type);
                  }),
                ),
            const Divider(),
            Wrap(spacing: 6, children: [
              _filterMenu('범위', _box, memoBoxes, memoBoxPath,
                (value) { _box = value; updateDrawer(() {}); }),
              _filterMenu('해시태그', _tag, tags, (item) => '#$item',
                (value) { _tag = value; updateDrawer(() {}); }),
              _filterMenu('첨부', _attachment, ['사진', '음성', '위치'], (item) => item,
                (value) { _attachment = value; updateDrawer(() {}); }),
              if (_box != null)
                FilterChip(label: const Text('하위 상자 포함'), selected: _descendants,
                  onSelected: (value) => update(() => _descendants = value)),
            ]),
            const Divider(),
            const ListTile(dense: true, title: Text('날짜')),
            RadioGroup<_SearchDate>(
              groupValue: _date,
              onChanged: (date) { if (date != null) update(() => _date = date); },
              child: Column(children: [
                for (final date in _SearchDate.values)
                  RadioListTile<_SearchDate>(dense: true, title: Text(date.label), value: date),
              ]),
            ),
          ],
        );
      })),
    );
  }

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
  void _queryChanged() {
    _debounce?.cancel();
    final value = widget.controller.text;
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(value));
  }
  @override void initState(){
    super.initState();
    elements.addListener(_refresh);
    widget.controller.addListener(_queryChanged);
  }
  @override void dispose(){_debounce?.cancel();elements.removeListener(_refresh);widget.controller.removeListener(_queryChanged);_scroll.dispose();super.dispose();}
  int _countSearchableItems() => searchWorkspace(widget.notes, elements.records.values,
      '', includeExtra: true).length;
  @override Widget build(BuildContext context){
    final results = _results ??= _filterResults(searchWorkspace(widget.notes,elements.records.values,_query, includeExtra: true));
    final terms = _searchTerms(_query).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final hasQuery = terms.isNotEmpty;
    final pattern = hasQuery
        ? RegExp(terms.map(RegExp.escape).join('|'), caseSensitive: false, unicode: true)
        : null;
    final total = _totalCount ??= _countSearchableItems();
    return Scaffold(endDrawer: _filters(), appBar:AppBar(centerTitle:false,titleSpacing:0,leadingWidth:44,title:const WorkspaceTitle('전체 보기'),actions:const[DesktopMenuAction()]),
      body:DesktopMenuBody(child:Column(children:[widget.selector,
        Padding(padding:const EdgeInsets.fromLTRB(12,4,8,0),child:Row(children:[Expanded(child:TextField(key:const ValueKey('workspace-search'),controller:widget.controller,
          style:TextStyle(fontSize:MediaQuery.sizeOf(context).width<1000?13:14),
          decoration:const InputDecoration(hintText:'자료 검색',prefixIcon:Icon(Icons.search,size:18),prefixIconConstraints:BoxConstraints(minWidth:36,minHeight:36),contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8),isDense:true),
          )), Builder(builder: (context) => IconButton(
            tooltip: '검색 필터',
            onPressed: () => Scaffold.of(context).openEndDrawer(),
            icon: Badge(isLabelVisible: _filtered, smallSize: 7, child: const Icon(Icons.tune, size: 21)),
          ))])),
        OverviewItemCount(hasQuery || _filtered
          ? '검색 결과 ${results.length}개 / 전체 ${total}개'
          : '자료 ${total}개'),
        Expanded(child:results.isEmpty?Center(child:Text(!hasQuery && !_filtered?'아직 자료가 없습니다.':'일치하는 자료가 없습니다.')):
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
              leading: Icon(switch (item.kind) {
                '문서' => Icons.description_outlined,
                '메모상자' => Icons.inventory_2_outlined,
                '음성텍스트' => Icons.transcribe_outlined,
                _ => Icons.chat_bubble_outline,
              }),
              title: _highlightedSearchText(context, item.title, pattern, 1, prefix: '${item.kind}: '),
              subtitle: _highlightedSearchText(context, preview, pattern, 3),
              onTap:()async{if(item.box case final box?){widget.onBox?.call(box);}else if(item.note!=null){if(widget.onDocument!=null){await widget.onDocument!(item.note!);}else{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProjectPage(project:item.note!.project!)));}}else{await showElementMetadata(context,item.record!.text);} _refresh();});
          }))),
      ])));
  }
}

import 'overview_collections.dart';
import 'thought_settings.dart';
import '../capture/geolog_page.dart';
import 'tag_colors.dart';
import 'desktop_menu_frame.dart';
import 'thought_filters.dart';
import 'thought_page.dart';
import 'memo_boxes.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'element_store.dart';
import 'word_badge.dart';
import 'workspace_routes.dart';
import 'workspace_storage.dart';

class ThoughtBoxView extends StatefulWidget {
  const ThoughtBoxView({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.initialBox, this.filters, this.viewSelector});
  final ThoughtFilterSelection? filters;
  final Widget? viewSelector;
  final List<Note> notes;
  final MemoBox? initialBox;
  final VoidCallback? onChanged;
  final VoidCallback? onLayoutChanged;
  @override
  State<ThoughtBoxView> createState() => _AllThoughtsPageState();
}

class _AllThoughtsPageState extends State<ThoughtBoxView> with RouteAware {
  String _query = '';
  final _textWidths = <String, double>{};
  bool _photosOnly = false, _audioOnly = false;
  late final _filters = widget.filters ?? ThoughtFilterSelection(initialBox: widget.initialBox);
  MemoBox? get _filterBox => _filters.singleBox;
  int _columns = 2;
  int _scaleColumns = 2;
  void _changed() { setState(() {}); widget.onChanged?.call(); }
  ModalRoute<dynamic>? _route;
  void _refresh() { _textWidths.clear(); if (mounted) setState(() {}); }
  @override
  void initState() { super.initState(); _filters.addListener(_refresh); elements.addListener(_refresh); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _textWidths.clear();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      workspaceRouteObserver.unsubscribe(this);
      workspaceRouteObserver.subscribe(this, route);
      _route = route;
    }
  }
  @override
  void didPopNext() => _refresh();
  @override
  void dispose() {
    workspaceRouteObserver.unsubscribe(this);
    _filters.removeListener(_refresh);
    if (widget.filters == null) _filters.dispose();
    elements.removeListener(_refresh);
    super.dispose();
  }
  Widget _badge(String word, bool desktop) => WordBadge(word: word, compact: true, fullText: true, query: _query,
    onTap: () => showElementMetadata(context, word));
  Widget _tile(ElementRecord record, bool desktop, {double width = 280}) {
    final tile = SizedBox(key: ValueKey('thought-${record.id}'), width: width, child: _badge(record.text, desktop));
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: 180, child: _badge(record.text, false)));
    if (desktop) { return Draggable<MemoDrag>(data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile); }
    return LongPressDraggable<MemoDrag>(data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile);
  }
  @override
  Widget build(BuildContext context) {
    final allRecords = elements.records.values.toList();
    final tags = {...allRecords.expand((record) => record.tags), ...hashtagColors.keys}.toList()..sort();
    final records = allRecords.where((record) => canBrowseThought(record) &&
      ((!_photosOnly && !_audioOnly) ||
        (_photosOnly && record.photos.isNotEmpty) ||
        (_audioOnly && record.recordings.isNotEmpty)) &&
      _filters.matches(record) &&
      (record.indexLabel.toLowerCase().contains(_query.toLowerCase()) || record.text.toLowerCase().contains(_query.toLowerCase()) || record.tags.any((tag) => tag.toLowerCase().contains(_query.toLowerCase().replaceFirst(RegExp(r'^#'), ''))))).toList();
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    final grid = LayoutBuilder(builder: (context, bounds) {
      final available = math.min(1000.0, math.max(0.0, bounds.maxWidth - 24));
      final maxWidth = desktop ? math.min(480.0, available)
        : (available * 2 / _columns).clamp(math.min(48.0, available), available);
      final rows = <List<({ElementRecord record, double width})>>[];
      var row = <({ElementRecord record, double width})>[];
      var used = 0.0;
      for (final record in records) {
        final textWidth = _textWidths.putIfAbsent(record.text, () {
          final painter = TextPainter(text: TextSpan(text: record.text,
            style: DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
            textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
          final width = painter.width; painter.dispose(); return width;
        });
        final width = (textWidth + 24).clamp(math.min(32.0, maxWidth), maxWidth).toDouble();
        if (row.isNotEmpty && used + 6 + width > available) {
          rows.add(row); row = []; used = 0;
        }
        used += (row.isEmpty ? 0 : 6) + width;
        row.add((record: record, width: width));
      }
      if (row.isNotEmpty) rows.add(row);
      return GestureDetector(
        onScaleStart: desktop ? null : (_) => _scaleColumns = _columns,
        onScaleUpdate: desktop ? null : (details) {
          if (details.pointerCount < 2) return;
          final next = (_scaleColumns / details.scale).round().clamp(1, 6);
          if (next != _columns) setState(() => _columns = next);
        },
        child: ListView.builder(key: const ValueKey('all-thoughts-grid'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          itemCount: 1 + (rows.isEmpty ? 1 : rows.length),
          itemBuilder: (context, index) {
            Widget child;
            if (index == 0) {
              child = Row(children: [
                Expanded(child: Text(_query.isEmpty && _filters.isEmpty ? '생각 ${records.length}개' : '생각 ${records.length}개 / 전체 ${allRecords.length}개', style: Theme.of(context).textTheme.bodyMedium)),
                if (!desktop) ...[
                  IconButton(tooltip: '확대', onPressed: _columns > 1 ? () => setState(() => _columns--) : null, icon: const Icon(Icons.zoom_in)),
                  Text('${(200 / _columns).round()}%', style: Theme.of(context).textTheme.bodyMedium),
                  IconButton(tooltip: '축소', onPressed: _columns < 6 ? () => setState(() => _columns++) : null, icon: const Icon(Icons.zoom_out)),
                ],
              ]);
            } else if (rows.isEmpty) {
              child = Padding(padding: const EdgeInsets.all(40), child: Text(allRecords.isEmpty ? '아직 생각이 없어요.' : _filterBox != null && _query.isEmpty ? '이 상자에 담긴 메모가 없어요.' : '일치하는 생각이 없어요.'));
            } else {
              final items = rows[index - 1];
              child = Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(
                mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _tile(items[i].record, desktop, width: items[i].width),
                ]],
              ));
            }
            return Center(child: SizedBox(width: available, child: child));
          }));
    });
    final footer = ThoughtFilters(tags: tags, selection: _filters,
      onChanged: _changed, onFilter: _filters.toggle);
    return Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle(_filterBox?.name ?? '전체 보기'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const DesktopMenuAction(),
      IconButton(tooltip: '사진 있는 생각', isSelected: _photosOnly,
        style: IconButton.styleFrom(backgroundColor: _photosOnly ? Theme.of(context).colorScheme.primaryContainer : null),
        icon: const Icon(Icons.image_outlined), onPressed: () => setState(() => _photosOnly = !_photosOnly)),
      IconButton(tooltip: '음성 있는 생각', isSelected: _audioOnly,
        style: IconButton.styleFrom(backgroundColor: _audioOnly ? Theme.of(context).colorScheme.primaryContainer : null),
        icon: const Icon(Icons.volume_up_outlined), onPressed: () => setState(() => _audioOnly = !_audioOnly)),
      IconButton(tooltip: '닫힌 생각 보기', icon: const Icon(Icons.archive_outlined), onPressed: () => showClosedThoughtsDialog(context)),
      IconButton(tooltip: '메모상자 만들기', icon: const Icon(Icons.inventory_2_outlined), onPressed: () async {
        final box = await createMemoBox(context); if (mounted && box != null) _changed();
      }),
      IconButton(tooltip: '사용 안내', icon: const Icon(Icons.info_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('생각 보기 안내'),
          content: const Text('생각이나 해시태그로 검색하고, 아래의 메모상자·태그를 눌러 분류별로 볼 수 있습니다.\n\n사진·음성 버튼을 켜면 해당 첨부가 있는 생각을 보여줍니다. 둘 다 켜면 사진 또는 음성이 있는 생각을 보여줍니다.\n\n생각을 메모상자로 드래그해 정리하세요. 모바일에서는 길게 눌러 드래그할 수 있습니다. 해시태그는 생각 본문에 #태그를 입력해 추가합니다.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))]))),
    ]))]),
      body: DesktopMenuBody(child: Column(children: [if (widget.viewSelector != null) widget.viewSelector!,
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: TextField(key: const ValueKey('all-thoughts-search'),
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: const InputDecoration(hintText: '생각·해시태그 찾기', prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true))),
        Expanded(child: SafeArea(child: grid)), footer])),
    );
  }
}

enum ThoughtView { documents, boxes, diagram, page, photos, audio, geolog }

class AllThoughtsPage extends StatefulWidget {
  const AllThoughtsPage({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.onSave, this.storage, this.onDocument, this.initialBox, this.initialView = ThoughtView.boxes});
  final List<Note> notes;
  final VoidCallback? onChanged, onLayoutChanged;
  final WorkspaceStorage? storage;
  final Future<void> Function(Note)? onDocument;
  final Future<void> Function()? onSave;
  final MemoBox? initialBox;
  final ThoughtView initialView;
  @override
  State<AllThoughtsPage> createState() => _ThoughtViewsState();
}
class _ThoughtViewsState extends State<AllThoughtsPage> with SingleTickerProviderStateMixin {
  late final AnimationController _tabPosition;
  late final _filters = ThoughtFilterSelection(initialBox: widget.initialBox);
  @override
  void initState() {
    super.initState();
    ensureUnclassifiedBox();
    _tabPosition=AnimationController(vsync:this,upperBound:ThoughtView.values.length-1.0,value:widget.initialView.index.toDouble());
  }
  @override
  void dispose() { _filters.dispose(); _tabPosition.dispose(); super.dispose(); }
  late ThoughtView _view = widget.initialView;
  @override
  Widget build(BuildContext context) {
    final selector=SingleChildScrollView(key:const PageStorageKey('overview-tabs'),scrollDirection:Axis.horizontal,child:SizedBox(height:40,width:ThoughtView.values.length*104,child:Stack(children:[
      AnimatedBuilder(animation:_tabPosition,builder:(context,_)=>Positioned(left:_tabPosition.value*104,top:0,bottom:0,width:104,child:ColoredBox(key:const ValueKey('thought-tab-highlight'),color:Theme.of(context).colorScheme.secondaryContainer))),
      Row(children:[for(final view in ThoughtView.values)SizedBox(width:104,height:40,child:Semantics(selected:view==_view,child:TextButton(style:TextButton.styleFrom(shape:const RoundedRectangleBorder()),onPressed:(){setState(()=>_view=view);_tabPosition.animateTo(view.index.toDouble(),duration:const Duration(milliseconds:200),curve:Curves.easeInOutCubic);},child:Text(switch(view){ThoughtView.documents=>'문서',ThoughtView.boxes=>'생각',ThoughtView.diagram=>'다이어그램',ThoughtView.page=>'메모상자',ThoughtView.photos=>'사진',ThoughtView.audio=>'음성',ThoughtView.geolog=>'지오로그'}))))])
    ])));
    if(_view==ThoughtView.documents)return DesktopMenuFrame(child:DocumentCollection(notes:widget.notes,selector:selector,storage:widget.storage,onOpen:widget.onDocument));
    if(_view==ThoughtView.photos || _view==ThoughtView.audio)return DesktopMenuFrame(child:AttachmentCollection(key:ValueKey(_view),audio:_view==ThoughtView.audio,selector:selector,filters:_filters,storage:widget.storage,onChanged:widget.onChanged));
    if (_view == ThoughtView.geolog) { return DesktopMenuFrame(child: GeologPage(filters: _filters, box: widget.initialBox,
      viewSelector: selector, onChanged: () => widget.onChanged?.call())); }
    if (_view == ThoughtView.boxes) { return DesktopMenuFrame(child: ThoughtBoxView(filters: _filters, notes: widget.notes, initialBox: widget.initialBox,
      onChanged: widget.onChanged, onLayoutChanged: widget.onLayoutChanged, viewSelector: selector)); }
    return DesktopMenuFrame(child: ThoughtPage(filters: _filters, key: ValueKey(_view), box: widget.initialBox, blocks: _view == ThoughtView.page,
      onChanged: () => widget.onChanged?.call(), onLayoutChanged: widget.onLayoutChanged, onSave:widget.onSave, viewSelector: selector));
  }
}

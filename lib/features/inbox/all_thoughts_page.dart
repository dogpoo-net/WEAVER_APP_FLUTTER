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
  const ThoughtBoxView({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.initialBox, this.viewSelector});
  final Widget? viewSelector;
  final List<Note> notes;
  final MemoBox? initialBox;
  final VoidCallback? onChanged;
  final VoidCallback? onLayoutChanged;
  @override
  State<ThoughtBoxView> createState() => _AllThoughtsPageState();
}

class _AllThoughtsPageState extends State<ThoughtBoxView> with RouteAware {
  String? _selectedId;
  String _query = '';
  MemoBox? _filterBox;
  String? _filterTag;
  void _filter({MemoBox? box, String? tag}) => setState(() {
    _filterBox = box; _filterTag = tag; _selectedId = null;
  });
  int _columns = 2;
  int _scaleColumns = 2;
  void _changed() { setState(() {}); widget.onChanged?.call(); }
  ModalRoute<dynamic>? _route;
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void initState() { super.initState(); _filterBox = widget.initialBox; elements.addListener(_refresh); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    elements.removeListener(_refresh);
    super.dispose();
  }
  ElementRecord? get _selected {
    for (final record in elements.records.values) { if (record.id == _selectedId) return record; }
    return null;
  }
  void _select(String word) {
    final id = elements.records[word]?.id;
    if (_selectedId != id) setState(() => _selectedId = id);
  }
  Widget _badge(String word, bool desktop) {
    final badge = WordBadge(
    word: word, compact: true, fullText: true, query: _query, selected: elements.records[word]?.id == _selectedId,
    onTap: desktop ? () => _select(word) : () => showElementMetadata(context, word),
    onDoubleTap: desktop ? () { _select(word); showElementMetadata(context, word); } : null,
    );
    return desktop ? Listener(
      onPointerDown: (event) { if (event.buttons == 1) _select(word); }, child: badge) : badge;
  }
  Widget _tile(ElementRecord record, bool desktop, {double width = 280}) {
    final tile = SizedBox(key: ValueKey('thought-${record.id}'), width: width, child: _badge(record.text, desktop));
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: 180, child: _badge(record.text, false)));
    if (desktop) { return Draggable<MemoDrag>(data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile); }
    return LongPressDraggable<MemoDrag>(data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile);
  }
  Widget _relations(bool desktop) {
    final selected = _selected;
    if (selected == null) { return const Center(child: Text('생각을 클릭하면 연결된 생각을 보여줍니다.')); }
    final related = elements.records.values.where((r) => selected.connections.contains(r.id) &&
      (widget.initialBox == null || widget.initialBox!.elementIds.contains(r.id)));
    return SingleChildScrollView(key: const ValueKey('thought-relations'), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('연결된 생각', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12), _badge(selected.text, desktop), const Divider(height: 24),
        if (related.isEmpty) const Text('연결된 생각이 없어요.'),
        for (final record in related) Padding(padding: const EdgeInsets.only(bottom: 6), child: _badge(record.text, desktop)),
      ]));
  }
  Future<void> _manageBox() async {
    final box = _filterBox;
    if (box == null) return;
    final selected = {...box.elementIds};
    var query = '';
    final result = await showDialog<Set<String>>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: const Text('상자에 담을 메모'),
        content: SizedBox(width: 420, height: 360, child: Column(children: [
          TextField(decoration: const InputDecoration(hintText: '메모에서 찾기', prefixIcon: Icon(Icons.search)),
            onChanged: (value) => update(() => query = value)),
          Expanded(child: ListView(children: [for (final record in elements.records.values)
            if (record.text.toLowerCase().contains(query.toLowerCase())) CheckboxListTile(
              title: Text(record.text, maxLines: 2, overflow: TextOverflow.ellipsis), value: selected.contains(record.id),
              onChanged: (checked) => update(() { if (checked == true) { selected.add(record.id); } else { selected.remove(record.id); } })),
          ])),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('담기'))],
      )));
    if (!mounted || result == null) return;
    box.elementIds..clear()..addAll(result);
    _changed();
  }
  @override
  Widget build(BuildContext context) {
    final allRecords = elements.records.values.where((r) => widget.initialBox == null || widget.initialBox!.elementIds.contains(r.id)).toList();
    final tags = allRecords.expand((record) => record.tags).toSet().toList()..sort();
    final records = allRecords.where((record) =>
      (_filterBox == null || _filterBox!.elementIds.contains(record.id)) &&
      (_filterTag == null || record.tags.contains(_filterTag)) &&
      record.text.toLowerCase().contains(_query.toLowerCase())).toList();
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    final grid = SingleChildScrollView(key: const ValueKey('all-thoughts-grid'), padding: EdgeInsets.all(desktop ? 24 : 8),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: Column(children: [
        Text(_query.isEmpty && _filterBox == null && _filterTag == null ? '원소 ${records.length}개' : '원소 ${records.length}개 / 전체 ${allRecords.length}개', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        TextField(key: const ValueKey('all-thoughts-search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(hintText: '원소에서 찾기', prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 32), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6), isDense: true)),
        const SizedBox(height: 12),
        if (!desktop) Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(tooltip: '확대', onPressed: _columns > 1 ? () => setState(() => _columns--) : null, icon: const Icon(Icons.zoom_in)),
          Text('${(200 / _columns).round()}%'),
          IconButton(tooltip: '축소', onPressed: _columns < 6 ? () => setState(() => _columns++) : null, icon: const Icon(Icons.zoom_out)),
        ]),
        if (records.isEmpty) Padding(padding: const EdgeInsets.all(40),
          child: Text(allRecords.isEmpty ? '아직 원소가 없어요.' : _filterBox != null && _query.isEmpty ? '이 상자에 담긴 메모가 없어요.' : '일치하는 원소가 없어요.')),
        LayoutBuilder(builder: (context, constraints) {
          final maxWidth = desktop ? math.min(480.0, constraints.maxWidth)
            : (constraints.maxWidth * 2 / _columns).clamp(48.0, constraints.maxWidth);
          final tiles = <Widget>[];
          for (final record in records) {
            final painter = TextPainter(text: TextSpan(text: record.text,
              style: DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
              textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
            final width = (painter.width + 24).clamp(32.0, maxWidth);
            painter.dispose();
            tiles.add(_tile(record, desktop, width: width));
          }
          return GestureDetector(
            onScaleStart: desktop ? null : (_) => _scaleColumns = _columns,
            onScaleUpdate: desktop ? null : (details) {
              if (details.pointerCount < 2) return;
              final next = (_scaleColumns / details.scale).round().clamp(1, 6);
              if (next != _columns) setState(() => _columns = next);
            },
            child: SizedBox(width: constraints.maxWidth, child: Wrap(
              alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: tiles)));
        }),
      ]))));
    final footer = ThoughtFilters(tags: tags, scope: widget.initialBox, box: _filterBox, tag: _filterTag,
      onChanged: _changed, onFilter: (box, tag) => _filter(box: box, tag: tag));
    return Scaffold(appBar: AppBar(titleSpacing: MediaQuery.sizeOf(context).width < 1000 ? 0 : null, leadingWidth: MediaQuery.sizeOf(context).width < 1000 ? 44 : null, title: WorkspaceTitle(widget.initialBox?.name ?? '모든 생각 보기'), actions: [const DesktopMenuAction(),
      if (_filterBox != null) IconButton(tooltip: '상자에 담을 메모 선택', onPressed: _manageBox, icon: const Icon(Icons.playlist_add)),
    ]),
      body: DesktopMenuBody(child: Column(children: [if (widget.viewSelector != null) widget.viewSelector!, Expanded(child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        if (desktop && constraints.maxWidth >= 760) { return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: grid), const VerticalDivider(width: 1), SizedBox(width: 320, child: _relations(desktop)),
        ]); }
        if (desktop) { return Column(children: [Expanded(child: grid),
          if (_selected != null) SizedBox(height: 260, child: _relations(desktop))]); }
        return grid;
      }))), footer])),
    );
  }
}

enum ThoughtView { boxes, diagram, page }

class AllThoughtsPage extends StatefulWidget {
  const AllThoughtsPage({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.initialBox, this.initialView = ThoughtView.diagram});
  final List<Note> notes;
  final VoidCallback? onChanged, onLayoutChanged;
  final MemoBox? initialBox;
  final ThoughtView initialView;
  @override
  State<AllThoughtsPage> createState() => _ThoughtViewsState();
}
class _ThoughtViewsState extends State<AllThoughtsPage> {
  late ThoughtView _view = widget.initialView;
  late ThoughtView _previousView = widget.initialView;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selector = SizedBox(height: 36, width: double.infinity, child: LayoutBuilder(builder: (context, bounds) => Stack(children: [
      TweenAnimationBuilder<double>(key: ValueKey(_view), tween: Tween(begin: _previousView.index.toDouble(), end: _view.index.toDouble()),
        duration: const Duration(milliseconds: 200), curve: Curves.easeInOutCubic,
        builder: (context, value, _) => Positioned(left: value * bounds.maxWidth / 3, top: 0, bottom: 0,
          width: bounds.maxWidth / 3, child: ColoredBox(color: colors.secondaryContainer))),
      Positioned.fill(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final view in ThoughtView.values) Expanded(child: Semantics(selected: view == _view,
        child: TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: const RoundedRectangleBorder(), foregroundColor: view == _view ? colors.onSecondaryContainer : colors.onSurface),
          onPressed: () => setState(() { _previousView = _view; _view = view; }),
          child: Text(switch (view) { ThoughtView.diagram => '다이어그램', ThoughtView.boxes => '상자', ThoughtView.page => '페이지' })))),
      ])),
    ])));
    if (_view == ThoughtView.boxes) { return DesktopMenuFrame(child: ThoughtBoxView(notes: widget.notes, initialBox: widget.initialBox,
      onChanged: widget.onChanged, onLayoutChanged: widget.onLayoutChanged, viewSelector: selector)); }
    return DesktopMenuFrame(child: ThoughtPage(key: ValueKey(_view), box: widget.initialBox, blocks: _view == ThoughtView.page,
      onChanged: () => widget.onChanged?.call(), onLayoutChanged: widget.onLayoutChanged, viewSelector: selector));
  }
}

import 'desktop_menu_frame.dart';
import 'tag_colors.dart';
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
  Widget _colorLabel(String label, Color color, VoidCallback onTap) => Tooltip(message: label,
    child: SizedBox.square(dimension: 24, child: InkWell(onTap: onTap,
      customBorder: const CircleBorder(), child: Icon(Icons.circle, color: color, size: 14))));

  Widget _filterChip({required Key key, required String label, required Color color,
    required String colorTooltip, required bool selected, required VoidCallback onFilter, required VoidCallback onColor}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      _colorLabel(colorTooltip, color, onColor),
      ChoiceChip(key: key, label: Text(label), selected: selected,
        showCheckmark: false, onSelected: (_) => onFilter()),
    ]);

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
              spacing: 6, runSpacing: 6, children: tiles)));
        }),
      ]))));
    return Scaffold(appBar: AppBar(titleSpacing: MediaQuery.sizeOf(context).width < 1000 ? 0 : null, leadingWidth: MediaQuery.sizeOf(context).width < 1000 ? 44 : null, title: WorkspaceTitle(widget.initialBox?.name ?? '모든 생각 보기'), actions: [const DesktopMenuAction(),
      if (_filterBox != null) IconButton(tooltip: '상자에 담을 메모 선택', onPressed: _manageBox, icon: const Icon(Icons.playlist_add)),
    ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 48, child: Row(children: [
            const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Icon(Icons.inventory_2_outlined, size: 18)),
            Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              key: const ValueKey('thought-filter-all'), label: const Text('전체'),
              selected: _filterBox == null && _filterTag == null, onSelected: (_) => _filter())),
            if (widget.initialBox == null) for (final box in memoBoxes) Padding(padding: const EdgeInsets.only(right: 6), child: MemoBoxTarget(
              box: box, onChanged: _changed, child: _filterChip(
                key: ValueKey('thought-filter-box-${box.name}'), label: box.name,
                color: Color(box.color), colorTooltip: '${box.name} 상자 색상 변경',
                selected: identical(_filterBox, box), onFilter: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => AllThoughtsPage(notes: widget.notes, initialBox: box, onLayoutChanged: widget.onLayoutChanged, onChanged: () { widget.onChanged?.call(); }))); if (mounted) setState(() {}); }, onColor: () async {
                  final color = await pickHashtagColor(context, box.name, Color(box.color), prefix: '');
                  if (!mounted || color == null) return;
                  box.color = color.toARGB32(); _changed();
                }))),
          ])), TextButton.icon(
            icon: const Icon(Icons.add, size: 18), label: const Text('상자 만들기'),
            onPressed: () async {
              final box = await createMemoBox(context);
              if (mounted && box != null) _changed();
            }),
          ])),
          if (tags.isNotEmpty) SizedBox(height: 44, child: Row(children: [
            const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Icon(Icons.tag, size: 18)),
            Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final tag in tags) Padding(padding: const EdgeInsets.only(right: 6), child: _filterChip(
                key: ValueKey('thought-filter-tag-$tag'), label: '#$tag', selected: _filterTag == tag,
                colorTooltip: '#$tag 색상 변경', color: hashtagColors.containsKey(tag)
                  ? Color(hashtagColors[tag]!) : Theme.of(context).colorScheme.outlineVariant,
                onFilter: () => _filter(tag: tag), onColor: () async {
                  final current = hashtagColors[tag];
                  final color = await pickHashtagColor(context, tag, current == null ? null : Color(current));
                  if (!mounted || color == null) return;
                  hashtagColors[tag] = color.toARGB32(); _changed();
                })),
            ])),
          ])),
        ]))),
      body: DesktopMenuBody(child: Column(children: [if (widget.viewSelector != null) widget.viewSelector!, Expanded(child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        if (desktop && constraints.maxWidth >= 760) { return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: grid), const VerticalDivider(width: 1), SizedBox(width: 320, child: _relations(desktop)),
        ]); }
        if (desktop) { return Column(children: [Expanded(child: grid),
          if (_selected != null) SizedBox(height: 260, child: _relations(desktop))]); }
        return grid;
      })))])),
    );
  }
}

enum ThoughtView { diagram, boxes, page }

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
  @override
  Widget build(BuildContext context) {
    final selector = Padding(padding: const EdgeInsets.only(bottom: 8), child: SegmentedButton<ThoughtView>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      style: TextButton.styleFrom(side: BorderSide.none, shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      segments: const [ButtonSegment(value: ThoughtView.diagram, label: Text('다이어그램')),
        ButtonSegment(value: ThoughtView.boxes, label: Text('상자')),
        ButtonSegment(value: ThoughtView.page, label: Text('페이지'))],
      selected: {_view}, onSelectionChanged: (value) => setState(() => _view = value.single),
    ));
    if (_view == ThoughtView.boxes) { return DesktopMenuFrame(child: ThoughtBoxView(notes: widget.notes, initialBox: widget.initialBox,
      onChanged: widget.onChanged, onLayoutChanged: widget.onLayoutChanged, viewSelector: selector)); }
    return DesktopMenuFrame(child: ThoughtPage(key: ValueKey(_view), box: widget.initialBox, blocks: _view == ThoughtView.page,
      onChanged: () => widget.onChanged?.call(), onLayoutChanged: widget.onLayoutChanged, viewSelector: selector));
  }
}

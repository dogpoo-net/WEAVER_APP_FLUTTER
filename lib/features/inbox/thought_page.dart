import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'element_store.dart';
import 'tag_colors.dart';
import 'hashtags.dart';
import 'memo_boxes.dart';
import 'memo_box_region.dart';
import 'word_badge.dart';
import 'graph_layout.dart';
import 'workspace_routes.dart';

/// A live workspace over the same thoughts, tags and reciprocal connections.
class ThoughtPage extends StatefulWidget {
  const ThoughtPage({super.key, required this.onChanged, this.onLayoutChanged, this.box});
  final VoidCallback onChanged;
  final VoidCallback? onLayoutChanged;
  final MemoBox? box;
  @override
  State<ThoughtPage> createState() => _ThoughtPageState();
}
class _ThoughtPageState extends State<ThoughtPage> with WidgetsBindingObserver, RouteAware {
  final _positions = <String, Offset>{};
  final _tagPositions = <String, Offset>{};
  String _query = '';
  bool _unlinkedOnly = false;
  final _view = TransformationController();
  Timer? _saveTimer;
  late final GraphLayout _layout;
  late final TextEditingController _search;
  String? _selected, _linkFrom;
  bool _linkMode = false, _centered = false;
  bool _routeVisible = true, _appActive = true;
  ModalRoute<dynamic>? _route;
  static const _nodeSize = Size(170, 76);
  @override
  void initState() {
    super.initState();
    _layout = widget.box?.layout ?? pageGraphLayout;
    _positions.addAll(_layout.positions);
    _tagPositions.addAll(_layout.tags);
    _query = _layout.query;
    _unlinkedOnly = _layout.unlinkedOnly;
    _search = TextEditingController(text: _query);
    if (_layout.viewport != null) {
      _view.value = Matrix4.fromList(_layout.viewport!);
      _centered = true;
    }
    _view.addListener(_saveLayout);
    WidgetsBinding.instance.addObserver(this);
    elements.addListener(_storeChanged);
    _sync();
  }
  void _saveLayout({bool flush = false}) {
    if (flush) {
      _saveTimer?.cancel(); _saveTimer = null;
      _flushLayout();
    } else {
      _saveTimer ??= Timer(const Duration(milliseconds: 250), () {
        _saveTimer = null;
        _flushLayout();
      });
    }
  }
  void _flushLayout() {
    _layout.positions..clear()..addAll(_positions);
    _layout.tags..clear()..addAll(_tagPositions);
    _layout.viewport = _view.value.storage.toList();
    _layout.query = _query;
    _layout.unlinkedOnly = _unlinkedOnly;
    (widget.onLayoutChanged ?? widget.onChanged)();
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      workspaceRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) workspaceRouteObserver.subscribe(this, route);
    }
  }
  @override
  void didPushNext() {
    _routeVisible = false;
    _saveLayout(flush: true);
  }
  @override
  void didPopNext() {
    _routeVisible = true;
    if (mounted) setState(_sync);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _saveLayout(flush: true);
    } else if (mounted && _routeVisible) {
      setState(_sync);
    }
  }
  List<ElementRecord> get _scopeRecords => elements.records.values.where((r) => widget.box == null || widget.box!.elementIds.contains(r.id)).toList();
  List<ElementRecord> get _records => _scopeRecords.where((r) =>
    (!_unlinkedOnly || r.connections.isEmpty) &&
    (_query.isEmpty || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  void _sync() {
    final records = _records;
    final scope = _scopeRecords;
    final scopeIds = scope.map((r) => r.id).toSet();
    _positions.removeWhere((id, _) => !scopeIds.contains(id));
    final scopeTags = scope.expand((r) => r.tags).map((tag) => 'tag:$tag').toSet();
    _tagPositions.removeWhere((tag, _) => !scopeTags.contains(tag));
    // Assign new thoughts once; existing nodes never move automatically.
    for (var i = 0; i < records.length; i++) {
      final angle = i * 2.39996;
      final radius = 65 + math.sqrt(i) * 70;
      _positions.putIfAbsent(records[i].id, () => Offset(1400 + math.cos(angle) * radius, 1000 + math.sin(angle) * radius));
    }
    final tags = records.expand((r) => r.tags).toSet().toList()..sort();
    for (var i = 0; i < tags.length; i++) {
      final members = records.where((r) => r.tags.contains(tags[i])).toList();
      final center = members.map((r) => _positions[r.id]!).reduce((a, b) => a + b) / members.length.toDouble();
      _tagPositions.putIfAbsent('tag:${tags[i]}', () => center + Offset(85 + (i % 3 - 1) * 100, -65 - (i % 2) * 45));
    }
    if (!records.any((r) => r.id == _selected)) _selected = null;
    _saveLayout();
  }
  void _storeChanged() { if (mounted && _routeVisible && _appActive) setState(_sync); }
  void _changed() { widget.onChanged(); setState(_sync); }
  Future<void> _create() async {
    var draft = '';
    final text = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('생각 만들기'), content: TextField(onChanged: (value) => draft = value, autofocus: true,
        minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '생각을 적어주세요')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: () { if (parseTaggedInput(draft).text.isNotEmpty) Navigator.pop(context, draft); }, child: const Text('만들기'))]));
    if (text == null || !mounted) return;
    final r = elements.add(text);
    widget.box?.elementIds.add(r.id);
    if (_selected != null) elements.connect(_selected!, [r.id]);
    _selected = r.id; _changed();
  }
  void _connect(String a, String b) {
    if (a == b) return;
    elements.connect(a, [b]); _linkFrom = null; _changed();
  }
  Future<void> _pick() async {
    final box = widget.box!;
    final selected = Set.of(box.elementIds);
    final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('상자에 생각 담기'), content: SizedBox(width: 400, height: 400, child: ListView(children: [
        for (final r in elements.records.values) CheckboxListTile(title: Text(badgeLabel(r.text), maxLines: 2, overflow: TextOverflow.ellipsis),
          value: selected.contains(r.id), onChanged: (yes) => update(() { if (yes == true) { selected.add(r.id); } else { selected.remove(r.id); } }))])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('적용'))])));
    if (accepted == true && mounted) { box.elementIds..clear()..addAll(selected); _changed(); }
  }
  @override
  void dispose() {
    _saveLayout(flush: true);
    WidgetsBinding.instance.removeObserver(this);
    workspaceRouteObserver.unsubscribe(this);
    elements.removeListener(_storeChanged);
    _view.removeListener(_saveLayout);
    _view.dispose(); _search.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final records = _records;
    final visiblePositions = {for (final r in records) r.id: _positions[r.id]!};
    final tags = records.expand((r) => r.tags).toSet().toList()..sort();
    final tagPositions = {for (final tag in tags) 'tag:$tag': _tagPositions['tag:$tag']!};
    final regions = <({MemoBox box, Rect bounds})>[];
    for (final box in widget.box == null ? memoBoxes : [widget.box!]) {
      final bounds = memoBoxCircleBounds(box.elementIds.where(visiblePositions.containsKey).map((id) => visiblePositions[id]!));
      if (bounds != null) regions.add((box: box, bounds: bounds));
    }
    final color = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(title: Text(widget.box?.name ?? '페이지'), actions: [
      if (widget.box != null) IconButton(tooltip: '상자에 생각 담기', onPressed: _pick, icon: const Icon(Icons.playlist_add)),
      IconButton(tooltip: '연결 모드', isSelected: _linkMode, onPressed: () => setState(() { _linkMode = !_linkMode; _linkFrom = null; }), icon: const Icon(Icons.link)),
      IconButton(tooltip: '생각 만들기', onPressed: _create, icon: const Icon(Icons.add)),
      IconButton(tooltip: '보기 초기화', onPressed: () => setState(() => _centered = false), icon: const Icon(Icons.center_focus_strong)),
    ]), body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: Row(children: [
        Expanded(child: TextField(key: const ValueKey('graph-search'), controller: _search,
          decoration: const InputDecoration(hintText: '생각·해시태그 찾기', prefixIcon: Icon(Icons.search), isDense: true),
          onChanged: (value) => setState(() { _query = value.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase(); _centered = false; _sync(); }))),
        const SizedBox(width: 8),
        FilterChip(label: const Text('연결 없음'), selected: _unlinkedOnly,
          onSelected: (value) => setState(() { _unlinkedOnly = value; _centered = false; _sync(); })),
      ])),
      Padding(padding: const EdgeInsets.all(8), child: Text(_linkMode
        ? '연결할 생각 두 개를 차례로 누르세요.' : '생각·태그를 드래그해 배치 · 연결 아이콘을 드롭해 연결 · 두 번 눌러 수정',
        style: Theme.of(context).textTheme.bodySmall)),
      Expanded(child: LayoutBuilder(builder: (context, viewport) {
        if (!_centered) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final points = [...visiblePositions.values, ...tagPositions.values,
              for (final region in regions) ...[region.bounds.topLeft, region.bounds.bottomRight]];
            if (points.isEmpty) points.add(const Offset(1400, 1000));
            final left = points.map((p) => p.dx).reduce(math.min), right = points.map((p) => p.dx).reduce(math.max) + 170;
            final top = points.map((p) => p.dy).reduce(math.min), bottom = points.map((p) => p.dy).reduce(math.max) + 76;
            final scale = math.min(viewport.maxWidth / (right - left + 120), viewport.maxHeight / (bottom - top + 120)).clamp(.15, 1.0);
            _view.value = Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(viewport.maxWidth / 2 - (left + right) / 2 * scale,
              viewport.maxHeight / 2 - (top + bottom) / 2 * scale, 0);
          });
        }
        return InteractiveViewer(
        onInteractionEnd: (_) => _saveLayout(flush: true),
        transformationController: _view, constrained: false, minScale: .15, maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(500),
        child: SizedBox(width: 3000, height: 2200, child: Stack(clipBehavior: Clip.none, children: [
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            {for (final entry in visiblePositions.entries) entry.key: entry.value + const Offset(85, 38), ...tagPositions},
            {for (final r in records) r.id: {...r.connections, ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty || _unlinkedOnly ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final record in records) Positioned(left: _positions[record.id]!.dx, top: _positions[record.id]!.dy,
            child: DragTarget<String>(onWillAcceptWithDetails: (d) => d.data != record.id,
              onAcceptWithDetails: (d) => _connect(d.data, record.id), builder: (context, candidates, _) => GestureDetector(
                onTap: () { if (_linkMode && _linkFrom != null) { _connect(_linkFrom!, record.id); }
                  else { setState(() { _selected = record.id; if (_linkMode) _linkFrom = record.id; }); } },
                onDoubleTap: () => showElementMetadata(context, record.text),
                onPanUpdate: (d) => setState(() { final p = _positions[record.id]! + d.delta / _view.value.getMaxScaleOnAxis();
                  _positions[record.id] = Offset(p.dx.clamp(0, 2830), p.dy.clamp(0, 2124)); _saveLayout(); }),
                onPanEnd: (_) => _saveLayout(flush: true), onPanCancel: () => _saveLayout(flush: true),
                child: Card(color: wordBackgroundColor(context, record.text),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
                    color: candidates.isNotEmpty || _selected == record.id ? color.primary : Colors.transparent, width: 2)),
                  child: SizedBox(width: _nodeSize.width, height: _nodeSize.height, child: Row(children: [
                    Expanded(child: Padding(padding: const EdgeInsets.all(10), child: Text(badgeLabel(record.text), maxLines: 2,
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: wordColor(context, record.text))))),
                    Draggable<String>(data: record.id, feedback: Material(child: Chip(label: Text(badgeLabel(record.text), overflow: TextOverflow.ellipsis))),
                      child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.link, size: 20))),
                  ])))),
            )),
          for (final tag in tags) Positioned(left: tagPositions['tag:$tag']!.dx - 60, top: tagPositions['tag:$tag']!.dy - 20,
            child: GestureDetector(key: ValueKey('graph-tag-$tag'), behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() {
                final p = _tagPositions['tag:$tag']! + d.delta / _view.value.getMaxScaleOnAxis();
                _tagPositions['tag:$tag'] = Offset(p.dx.clamp(60, 2900), p.dy.clamp(20, 2160)); _saveLayout();
              }),
              onPanEnd: (_) => _saveLayout(flush: true), onPanCancel: () => _saveLayout(flush: true),
              child: DragTarget<String>(onAcceptWithDetails: (d) {
              final r = records.where((r) => r.id == d.data).firstOrNull;
              if (r != null) { r.tags.add(tag); _changed(); }
            }, builder: (context, candidates, _) => Chip(label: Text('#$tag'),
              backgroundColor: Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: candidates.isEmpty ? .3 : .6))))),
        ])),
      ); })),
      if (_selected != null) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton.icon(onPressed: () { final r = records.where((r) => r.id == _selected).firstOrNull;
          if (r != null) showElementMetadata(context, r.text); }, icon: const Icon(Icons.edit_outlined), label: const Text('생각 수정')),
        TextButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('연결된 생각 만들기')),
      ]),
      SizedBox(height: 54, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final tag in tags) Padding(padding: const EdgeInsets.only(right: 6), child: DragTarget<String>(
          onAcceptWithDetails: (d) { final r = records.where((r) => r.id == d.data).firstOrNull;
            if (r != null) { r.tags.add(tag); _changed(); } },
          builder: (context, candidates, _) => Chip(backgroundColor: Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: candidates.isEmpty ? .2 : .5), label: Text('#$tag')))),
      ])),
    ]));
  }
}
class _Connections extends CustomPainter {
  _Connections(this.positions, this.links, this.color, this.tagColors);
  final Map<String, Color> tagColors;
  final Map<String, Offset> positions;
  final Map<String, Set<String>> links;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..color = color..strokeWidth = 1.5;
    for (final entry in links.entries) {
      for (final id in entry.value) {
        if ((tagColors.containsKey(id) || entry.key.compareTo(id) < 0) && positions.containsKey(id) && positions.containsKey(entry.key)) {
          pen.color = tagColors[id]?.withValues(alpha: .75) ?? color;
          canvas.drawLine(positions[entry.key]!, positions[id]!, pen);
        }
      }
    }
  }
  @override
  bool shouldRepaint(covariant _Connections oldDelegate) =>
    color != oldDelegate.color || !mapEquals(positions, oldDelegate.positions) ||
    !mapEquals(tagColors, oldDelegate.tagColors) || links.length != oldDelegate.links.length ||
    links.entries.any((entry) => !setEquals(entry.value, oldDelegate.links[entry.key]));
}

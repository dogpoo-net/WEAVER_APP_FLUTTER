import 'thought_filters.dart';
import 'desktop_menu_frame.dart';
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
import 'thought_interaction.dart';
import 'workspace_routes.dart';
import 'graph_arrangement.dart';

/// A live workspace over the same thoughts, tags and reciprocal connections.
class ThoughtPage extends StatefulWidget {
  const ThoughtPage({super.key, required this.onChanged, this.onLayoutChanged, this.box, this.blocks = false, this.viewSelector});
  final VoidCallback onChanged;
  final VoidCallback? onLayoutChanged;
  final MemoBox? box;
  final bool blocks;
  final Widget? viewSelector;
  @override
  State<ThoughtPage> createState() => _ThoughtPageState();
}
class _ThoughtPageState extends State<ThoughtPage> with WidgetsBindingObserver, RouteAware {
  final _sceneKey = GlobalKey();
  final _emptyBoxBounds = <MemoBox, Rect>{};
  final _positions = <String, Offset>{};
  final _tagPositions = <String, Offset>{};
  String _query = '';
  MemoBox? _filterBox;
  String? _filterTag;
  bool _unlinkedOnly = false;
  final _view = TransformationController();
  Timer? _saveTimer;
  late final GraphLayout _layout;
  late final TextEditingController _search;
  String? _selected, _linkFrom, _draggingId;
  MemoBox? _hoverBox;
  final _liftBoxes = <MemoBox, Rect>{};
  bool _linkMode = false, _centered = false;
  bool _routeVisible = true, _appActive = true;
  ModalRoute<dynamic>? _route;
  Size _size(String id) { final p = _layout.sizes[id]; return p == null ? (widget.blocks ? const Size(230, 110) : graphThoughtSize) : Size(p.dx, p.dy); }
  Rect _bounds(String id) => _positions[id]! & _size(id);
  @override
  void initState() {
    super.initState();
    final base = widget.box?.layout ?? pageGraphLayout;
    _layout = widget.blocks ? base.blockLayout : base;
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
    (_filterBox == null || _filterBox!.elementIds.contains(r.id)) &&
    (_filterTag == null || r.tags.contains(_filterTag)) &&
    (!_unlinkedOnly || r.connections.isEmpty) &&
    (_query.isEmpty || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  void _sync() {
    final records = _records;
    final scope = _scopeRecords;
    final hadPositions = _positions.isNotEmpty;
    final scopeIds = scope.map((r) => r.id).toSet();
    _positions.removeWhere((id, _) => !scopeIds.contains(id));
    final scopeTags = scope.expand((r) => r.tags).map((tag) => 'tag:$tag').toSet();
    _tagPositions.removeWhere((tag, _) => !scopeTags.contains(tag));
    var left = 32.0, top = 32.0;
    for (final p in [..._positions.values, ..._tagPositions.values]) { left = math.min(left, p.dx); top = math.min(top, p.dy); }
    for (final box in _filterBox != null ? [_filterBox!] : (widget.box == null ? memoBoxes : [widget.box!])) {
      final bounds = _regionBounds(box, _positions);
      if (bounds != null) { left = math.min(left, bounds.left); top = math.min(top, bounds.top); }
    }
    if (left < 32 || top < 32) {
      final shift = Offset(32 - left, 32 - top);
      _positions.updateAll((id, p) => p + shift);
      _tagPositions.updateAll((id, p) => p + shift);
      _centered = false;
    }
    final tags = scope.expand((r) => r.tags).toSet().toList()..sort();
    final ordered = [...scope]..sort((a, b) {
      final at = a.tags.toList()..sort(), bt = b.tags.toList()..sort();
      final order = (at.firstOrNull ?? '\uffff').compareTo(bt.firstOrNull ?? '\uffff');
      return order != 0 ? order : a.createdAt.compareTo(b.createdAt);
    });
    if (widget.blocks) {
      _arrangeBlocks(ordered);
    } else {
      arrangeGraph(thoughts: ordered.map((r) => r.id).toList(), tags: tags,
        positions: _positions, tagPositions: _tagPositions,
        sizes: {for (final id in _positions.keys) id: _size(id)});
      if (!hadPositions && widget.box == null) _separateBoxes();
    }
    if (!hadPositions && _positions.isNotEmpty) _centered = false;
    if (!records.any((r) => r.id == _selected)) _selected = null;
    _saveLayout();
  }
  void _arrangeBlocks(List<ElementRecord> records) {
    final ordered = [...records]..sort((a, b) {
      String group(ElementRecord r) => '${memoBoxes.where((box) => box.elementIds.contains(r.id)).map((box) => box.name).join('|')}:${(r.tags.toList()..sort()).join('|')}';
      return group(a).compareTo(group(b));
    });
    var index = 0;
    for (final record in ordered) {
      _positions.putIfAbsent(record.id, () => Offset(640 + (index % 4) * 290, 400 + (index ~/ 4) * 170));
      index++;
    }
  }
  Rect? _regionBounds(MemoBox box, Map<String, Offset> positions) {
    final ids = box.elementIds.where(positions.containsKey).toList();
    if (ids.isEmpty) return null;
    if (widget.blocks) return ids.map((id) => positions[id]! & _size(id)).reduce((a, b) => a.expandToInclude(b)).inflate(32);
    return memoBoxCircleBounds(ids.map((id) => positions[id]!), sizes: {for (final id in ids) positions[id]!: _size(id)});
  }
  bool _inside(Rect bounds, Offset point) => widget.blocks ? bounds.contains(point) : (point - bounds.center).distance <= bounds.width / 2;
  void _separateBoxes() {
    var x = 640.0;
    final assigned = <String>{};
    final top = _tagPositions.values.map((p) => tagBounds(p).bottom + 100).fold(400.0, math.max);
    var bottom = top;
    for (final box in memoBoxes) {
      final ids = box.elementIds.where((id) => _positions.containsKey(id) && !assigned.contains(id)).toList();
      if (ids.isEmpty) continue;
      for (var i = 0; i < ids.length; i++) { _positions[ids[i]] = Offset(x + (i % 3) * 220, 600 + (i ~/ 3) * 140); }
      final bounds = memoBoxCircleBounds(ids.map((id) => _positions[id]!))!;
      final shift = Offset(x - bounds.left, math.max(0, top - bounds.top));
      for (final id in ids) { _positions[id] = _positions[id]! + shift; }
      final moved = bounds.shift(shift);
      x = moved.right + 100; bottom = math.max(bottom, moved.bottom);
      assigned.addAll(ids);
    }
    var i = 0;
    for (final id in _positions.keys.where((id) => !assigned.contains(id)).toList()) {
      _positions[id] = Offset(640 + (i % 6) * 250, bottom + 120 + (i ~/ 6) * 160); i++;
    }
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
  Future<void> _disconnect() async {
    final record = elements.records.values.where((r) => r.id == _selected).firstOrNull;
    if (record == null) return;
    final targets = elements.records.values.where((r) => record.connections.contains(r.id)).toList();
    final choice = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('연결 끊기'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (targets.isEmpty && record.tags.isEmpty) const Text('연결된 생각이나 태그가 없습니다.'),
        for (final target in targets) ListTile(title: Text(badgeLabel(target.text), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.link_off), onTap: () => Navigator.pop(context, target.id)),
        for (final tag in record.tags) ListTile(title: Text('#$tag'), trailing: const Icon(Icons.link_off),
          onTap: () => Navigator.pop(context, 'tag:$tag')),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    ));
    if (choice == null || !mounted) return;
    if (choice.startsWith('tag:')) {
      record.tags.remove(choice.substring(4));
    } else {
      elements.disconnect(record.id, choice);
    }
    _changed();
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
    final tagPositions = <String, Offset>{if (!widget.blocks) for (final tag in tags) 'tag:$tag': _tagPositions['tag:$tag']!};
    final nodeRects = <String, Rect>{
      for (final e in visiblePositions.entries) e.key: _bounds(e.key),
      for (final e in tagPositions.entries) e.key: tagBounds(e.value),
    };
    var sceneWidth = math.max(3000.0, nodeRects.values.map((r) => r.right + 100).fold(0.0, math.max));
    var sceneHeight = math.max(2200.0, nodeRects.values.map((r) => r.bottom + 100).fold(0.0, math.max));
    final regions = <({MemoBox box, Rect bounds})>[];
    for (final box in _filterBox != null ? [_filterBox!] : (widget.box == null ? memoBoxes : [widget.box!])) {
      final bounds = _regionBounds(box, visiblePositions);
      if (bounds != null) regions.add((box: box, bounds: _liftBoxes[box] ?? bounds));
    }
    var emptyX = regions.map((r) => r.bounds.right + 80).fold(
      nodeRects.values.map((r) => r.right + 80).fold(640.0, math.max), math.max);
    for (final box in _filterBox != null ? [_filterBox!] : (widget.box == null ? memoBoxes : [widget.box!])) {
      if (box.elementIds.any(_positions.containsKey)) continue;
      regions.add((box: box, bounds: _emptyBoxBounds.putIfAbsent(box, () => Rect.fromLTWH(emptyX, 440, 260, 260))));
      emptyX += 340;
    }
    final tagRegions = <({String tag, Rect bounds})>[];
    if (widget.blocks) { for (final tag in tags) {
      final members = records.where((r) => r.tags.contains(tag) && visiblePositions.containsKey(r.id)).toList();
      final bounds = memoBoxCircleBounds(members.map((r) => visiblePositions[r.id]!),
        sizes: {for (final r in members) visiblePositions[r.id]!: _size(r.id)});
      if (bounds != null) tagRegions.add((tag: tag, bounds: bounds));
    }
    }
    for (final region in tagRegions) {
      sceneWidth = math.max(sceneWidth, region.bounds.right + 100);
      sceneHeight = math.max(sceneHeight, region.bounds.bottom + 100);
    }
    sceneWidth = regions.map((r) => r.bounds.right + 100).fold(sceneWidth, math.max);
    sceneHeight = regions.map((r) => r.bounds.bottom + 100).fold(sceneHeight, math.max);
    final color = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(titleSpacing: MediaQuery.sizeOf(context).width < 1000 ? 0 : null, leadingWidth: MediaQuery.sizeOf(context).width < 1000 ? 44 : null, title: WorkspaceTitle(widget.box?.name ?? '모든 생각 보기'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const DesktopMenuAction(),
      if (widget.box != null) IconButton(tooltip: '상자에 생각 담기', onPressed: _pick, icon: const Icon(Icons.playlist_add)),
      IconButton(tooltip: '연결 모드', style: IconButton.styleFrom(backgroundColor: _linkMode ? color.primaryContainer : null, foregroundColor: _linkMode ? color.onPrimaryContainer : null), isSelected: _linkMode, onPressed: () => setState(() { _linkMode = !_linkMode; _linkFrom = null; }), icon: const Icon(Icons.link)),
      IconButton(tooltip: '생각 만들기', onPressed: _create, icon: const Icon(Icons.add)),
      IconButton(tooltip: '전체 위치 보기', onPressed: () => setState(() => _centered = false), icon: const Icon(Icons.center_focus_strong)),
      IconButton(tooltip: '사용 안내', icon: const Icon(Icons.info_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('사용 안내'),
          content: const Text('생각·태그를 드래그해 배치하고, 연결 아이콘을 드롭해 연결하세요. 생각을 두 번 누르면 수정할 수 있습니다. 연결 모드에서는 생각 두 개를 차례로 누르세요.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))]))),
    ]))]), body: DesktopMenuBody(child: Column(children: [
      if (widget.viewSelector != null) widget.viewSelector!,
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: Row(children: [
        Expanded(child: TextField(key: const ValueKey('graph-search'), controller: _search,
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
          decoration: const InputDecoration(hintText: '생각·해시태그 찾기', prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          onChanged: (value) => setState(() { _query = value.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase(); _centered = false; _sync(); }))),
        const SizedBox(width: 8),
        FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero, label: const Text('연결 없음', style: TextStyle(fontSize: 12)), selected: _unlinkedOnly,
          onSelected: (value) => setState(() { _unlinkedOnly = value; _centered = false; _sync(); })),
      ])),
      if (_linkMode) const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text('생각 두 개를 차례로 눌러 연결하거나 해제하세요.', style: TextStyle(fontSize: 12))),
      Expanded(child: LayoutBuilder(builder: (context, viewport) {
        if (!_centered) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final points = [...visiblePositions.values, ...tagPositions.values,
              for (final region in [...regions.map((r) => r.bounds), ...tagRegions.map((r) => r.bounds)]) ...[region.topLeft, region.bottomRight]];
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
        transformationController: _view, scaleFactor: 1000, constrained: false, minScale: .15, maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(500),
        child: SizedBox(key: _sceneKey, width: sceneWidth, height: sceneHeight, child: Stack(clipBehavior: Clip.none, children: [
          for (final region in tagRegions) Positioned.fromRect(rect: region.bounds,
            child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
              color: Color(hashtagColors[region.tag] ?? 0xFF90A4AE).withValues(alpha: .10),
              border: Border.all(color: Color(hashtagColors[region.tag] ?? 0xFF90A4AE).withValues(alpha: .65), width: 2)),
              child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 12),
                child: Text('#${region.tag}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))))))),
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds, highlighted: identical(_hoverBox, region.box), rectangular: widget.blocks,
            onDrag: (delta) => setState(() {
              final empty = !region.box.elementIds.any(_positions.containsKey);
              final current = empty ? (_emptyBoxBounds[region.box] ?? region.bounds) : (_regionBounds(region.box, _positions) ?? region.bounds);
              final shift = Offset(math.max(delta.dx, 32 - current.left), math.max(delta.dy, 32 - current.top));
              if (empty) { _emptyBoxBounds[region.box] = current.shift(shift); }
              for (final id in region.box.elementIds.where(_positions.containsKey)) { _positions[id] = _positions[id]! + shift; }
              _saveLayout();
            }), onDragEnd: () => _saveLayout(flush: true)),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            nodeRects,
            {for (final r in records) r.id: {...r.connections, if (!widget.blocks) ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty || _unlinkedOnly ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final record in records) Positioned(left: _positions[record.id]!.dx, top: _positions[record.id]!.dy,
            child: DragTarget<String>(onWillAcceptWithDetails: (d) => d.data != record.id,
              onAcceptWithDetails: (d) => _connect(d.data, record.id), builder: (context, candidates, _) => ThoughtInteraction(size: _size(record.id), desktop: MediaQuery.sizeOf(context).width >= 760,
                onLift: () => setState(() {
                  _liftBoxes..clear()..addEntries(regions.where((r) => r.box.elementIds.contains(record.id)).map((r) => MapEntry(r.box, r.bounds)));
                }),
                onActiveChanged: (active) => setState(() { _draggingId = active ? record.id : null; if (!active) _hoverBox = null; }),
                onTap: () { if (_linkMode && _linkFrom != null) {
                  final from = _linkFrom!;
                  if (from != record.id && record.connections.contains(from)) {
                    elements.disconnect(from, record.id); _linkFrom = null; _changed();
                  } else { _connect(from, record.id); }
                }
                  else { setState(() { _selected = record.id; if (_linkMode) _linkFrom = record.id; }); } },
                onDoubleTap: () => showElementMetadata(context, record.text),
                onMove: (delta) => setState(() { final p = _positions[record.id]! + delta; _positions[record.id] = Offset(math.max(32, p.dx), math.max(32, p.dy));
                  final center = _bounds(record.id).center;
                  _hoverBox = regions.where((r) => !r.box.elementIds.contains(record.id) && _inside(r.bounds, center)).firstOrNull?.box;
                  _saveLayout(); }),
                onResize: (size, shift) => setState(() {
                  _layout.sizes[record.id] = Offset(size.width, size.height);
                  final p = _positions[record.id]! + shift; _positions[record.id] = Offset(math.max(32, p.dx), math.max(32, p.dy)); _saveLayout();
                }),
                onDrop: (pointer) {
                  final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
                  final center = scene?.globalToLocal(pointer) ?? _bounds(record.id).center;
                  final detached = <MemoBox>{};
                  for (final entry in _liftBoxes.entries) {
                    if (!_inside(entry.value, center)) {
                      entry.key.elementIds.remove(record.id); detached.add(entry.key);
                      _emptyBoxBounds[entry.key] = entry.value;
                    }
                  }
                  final targets = regions.where((r) => !detached.contains(r.box) && !r.box.elementIds.contains(record.id) &&
                    _inside(r.bounds, center)).toList()
                    ..sort((a, b) => a.bounds.width.compareTo(b.bounds.width));
                  if (targets.isNotEmpty) {
                    targets.first.box.elementIds.add(record.id);
                    _changed();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${targets.first.box.name}에 담았습니다.')));
                  }
                  if (detached.isNotEmpty) _changed();
                  _saveLayout(flush: true);
                }, onEnd: () { setState(() { _liftBoxes.clear(); _draggingId = null; _hoverBox = null; }); _saveLayout(flush: true); },
                child: Card(color: wordBackgroundColor(context, record.text),
                  shape: widget.blocks ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: _draggingId == record.id || _selected == record.id ? color.primary : color.outlineVariant, width: 2)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
                    color: candidates.isNotEmpty || _selected == record.id || _draggingId == record.id ? color.primary : Colors.transparent, width: _draggingId == record.id ? 3 : 2)),
                  child: SizedBox(width: _size(record.id).width - 8, height: _size(record.id).height - 8, child: Column(children: [
                    if (widget.blocks && record.tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 0), child: Align(alignment: Alignment.centerLeft,
                      child: Text(record.tags.map((tag) => '#$tag').join('  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)))),
                    Expanded(child: Row(children: [
                    Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Text(badgeLabel(record.text), maxLines: ((_size(record.id).height - 24 - (widget.blocks && record.tags.isNotEmpty ? 24 : 0)) / 22).floor().clamp(1, 20),
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: wordColor(context, record.text))))),
                    Draggable<String>(data: record.id, feedback: Material(child: Chip(label: Text(badgeLabel(record.text), overflow: TextOverflow.ellipsis))),
                      child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.link, size: 20))),
                  ])),
                  ])))),
            )),
          if (!widget.blocks) for (final tag in tags) Positioned(left: tagBounds(tagPositions['tag:$tag']!).left, top: tagBounds(tagPositions['tag:$tag']!).top,
            width: graphTagSize.width, height: graphTagSize.height,
            child: GestureDetector(key: ValueKey('graph-tag-$tag'), behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() {
                final p = _tagPositions['tag:$tag']! + d.delta;
                _tagPositions['tag:$tag'] = Offset(p.dx.clamp(graphTagSize.width / 2, sceneWidth - graphTagSize.width / 2), p.dy.clamp(graphTagSize.height / 2, sceneHeight - graphTagSize.height / 2)); _saveLayout();
              }),
              onPanEnd: (_) => _saveLayout(flush: true), onPanCancel: () => _saveLayout(flush: true),
              child: DragTarget<String>(onAcceptWithDetails: (d) {
              final r = records.where((r) => r.id == d.data).firstOrNull;
              if (r != null) { r.tags.add(tag); _changed(); }
            }, builder: (context, candidates, _) => Tooltip(message: '#$tag', child: Chip(side: BorderSide(color: Color(hashtagColors[tag] ?? 0xFF90A4AE), width: 2.5), label: Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis),
              backgroundColor: Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: candidates.isEmpty ? .3 : .6)))))),
        ])),
      ); })),
      if (_selected != null) Wrap(alignment: WrapAlignment.center, children: [
        TextButton.icon(onPressed: () { final r = records.where((r) => r.id == _selected).firstOrNull;
          if (r != null) showElementMetadata(context, r.text); }, icon: const Icon(Icons.edit_outlined), label: const Text('생각 수정')),
        TextButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('연결된 생각 만들기')),
        TextButton.icon(onPressed: _disconnect, icon: const Icon(Icons.link_off), label: const Text('연결 끊기')),
      ]),
      ThoughtFilters(tags: _scopeRecords.expand((r) => r.tags).toSet().toList()..sort(), scope: widget.box,
        box: _filterBox, tag: _filterTag, onChanged: _changed,
        onFilter: (box, tag) => setState(() { _filterBox = box; _filterTag = tag; _selected = null; _linkFrom = null; _centered = false; _sync(); })),
    ])));
  }
}
class _Connections extends CustomPainter {
  _Connections(this.positions, this.links, this.color, this.tagColors);
  final Map<String, Color> tagColors;
  final Map<String, Rect> positions;
  final Map<String, Set<String>> links;
  final Color color;
  late final List<({Path path, Color color})> _paths = _buildPaths();
  List<({Path path, Color color})> _buildPaths() {
    final result = <({Path path, Color color})>[];

    for (final entry in links.entries) {
      for (final id in entry.value) {
        if ((tagColors.containsKey(id) || entry.key.compareTo(id) < 0) && positions.containsKey(id) && positions.containsKey(entry.key)) {
          final points = [positions[entry.key]!.center, positions[id]!.center];
          final path = Path()..moveTo(points.first.dx, points.first.dy);
          for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
          result.add((path: path, color: tagColors[id]?.withValues(alpha: .75) ?? color));
        }
      }
    }
    return result;
  }
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round;
    for (final edge in _paths) {
      pen.color = edge.color;
      canvas.drawPath(edge.path, pen);
    }
  }
  @override
  bool shouldRepaint(covariant _Connections oldDelegate) =>
    color != oldDelegate.color || !mapEquals(positions, oldDelegate.positions) ||
    !mapEquals(tagColors, oldDelegate.tagColors) || links.length != oldDelegate.links.length ||
    links.entries.any((entry) => !setEquals(entry.value, oldDelegate.links[entry.key]));
}

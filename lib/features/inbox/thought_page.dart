import 'thought_settings.dart';
import '../capture/attachment_indicators.dart';
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
  String? _linkFrom, _draggingId;
  MemoBox? _hoverBox;
  final _liftBoxes = <MemoBox, Rect>{};
  bool _linkMode = false, _centered = false;
  bool _routeVisible = true, _appActive = true;
  ModalRoute<dynamic>? _route;
  Size _size(String id) { final p = _layout.sizes[id]; return p == null ? (widget.blocks ? const Size(230, 120) : graphThoughtSize) : Size(p.dx, p.dy); }
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
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 250), () {
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
  List<ElementRecord> get _scopeRecords {
    final ids = widget.box?.subtreeElementIds;
    return elements.records.values.where((r) => ids == null || ids.contains(r.id)).toList();
  }
  List<ElementRecord> get _records {
    final ids = _filterBox?.subtreeElementIds;
    return _scopeRecords.where((r) => canBrowseThought(r) &&
    (ids == null || ids.contains(r.id)) &&
    (_filterTag == null || r.tags.contains(_filterTag)) &&
    (!_unlinkedOnly || r.connections.isEmpty) &&
    (_query.isEmpty || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  }
  void _sync() {
    final records = _records;
    final scope = _scopeRecords;
    final hadPositions = _positions.isNotEmpty;
    final newIds = scope.where((r) => !_positions.containsKey(r.id)).map((r) => r.id).toSet();
    final scopeIds = scope.map((r) => r.id).toSet();
    _positions.removeWhere((id, _) => !scopeIds.contains(id));
    final scopeTags = scope.expand((r) => r.tags).map((tag) => 'tag:$tag').toSet();
    _tagPositions.removeWhere((tag, _) => !scopeTags.contains(tag));
    var left = 32.0, top = 32.0;
    for (final p in [..._positions.values, ..._tagPositions.values]) { left = math.min(left, p.dx); top = math.min(top, p.dy); }
    for (final box in _regionBoxes) {
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
    _separateOverlappingBoxes();
    if (hadPositions || widget.blocks) {
      final loose = newIds.where((id) => !memoBoxes.any((box) => !box.isUnclassified && box.elementIds.contains(id))).toList();
      final occupied = [
        for (final id in _positions.keys.where((id) => !loose.contains(id))) _bounds(id),
        for (final box in _allRegionBoxes) ?_boxBounds(box),
        if (!widget.blocks) for (final point in _tagPositions.values) tagBounds(point),
      ];
      final y = occupied.map((r) => r.bottom).fold(400.0, math.max) + 120;
      for (var i = 0; i < loose.length; i++) {
        _positions[loose[i]] = Offset(640 + (i % 5) * 290, y + (i ~/ 5) * 180);
      }
    }
    if (!hadPositions && _positions.isNotEmpty) _centered = false;
    if (!records.any((r) => r.id == _linkFrom)) _linkFrom = null;
    _saveLayout();
  }
  void _arrangeBlocks(List<ElementRecord> records) {
    final ordered = [...records]..sort((a, b) {
      String group(ElementRecord r) => '${memoBoxes.where((box) => !box.isUnclassified && box.elementIds.contains(r.id)).map((box) => box.name).join('|')}:${(r.tags.toList()..sort()).join('|')}';
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
    if (ids.isEmpty && (!widget.blocks || box.children.isEmpty)) return null;
    if (widget.blocks) {
      final parts = <Rect>[for (final id in ids) positions[id]! & _size(id),
        for (final child in box.children) _liftBoxes[child] ?? _regionBounds(child, positions) ?? _emptyBoxBounds.putIfAbsent(child,
          () => Rect.fromLTWH(640 + memoBoxes.indexOf(child) * 340, 440, 260, 260))];
      return parts.isEmpty ? null : parts.reduce((a, b) => a.expandToInclude(b)).inflate(32);
    }
    return memoBoxCircleBounds(ids.map((id) => positions[id]!), sizes: {for (final id in ids) positions[id]!: _size(id)});
  }
  bool _inside(Rect bounds, Offset point) => widget.blocks ? bounds.contains(point) : (point - bounds.center).distance <= bounds.width / 2;
  Set<String> _boxMembers(MemoBox box) => widget.blocks ? box.subtreeElementIds : box.elementIds;
  Iterable<MemoBox> _withChildren(Iterable<MemoBox> boxes) {
    final result = {for (final box in boxes) box, if (widget.blocks) ...memoBoxes.where((candidate) => boxes.any((box) => box.isAncestorOf(candidate)))}.where((b) => !b.isUnclassified).toList();
    result.sort((a, b) => a.depth.compareTo(b.depth));
    return result;
  }
  Iterable<MemoBox> get _regionBoxes => _withChildren(_filterBox != null ? [_filterBox!] : (widget.box == null ? memoBoxes : [widget.box!]));
  Iterable<MemoBox> get _allRegionBoxes => _withChildren(widget.box == null ? memoBoxes : [widget.box!]);
  void _moveBox(MemoBox box, Offset shift) {
    for (final id in _boxMembers(box).where(_positions.containsKey)) { _positions[id] = _positions[id]! + shift; }
    for (final member in [box, if (widget.blocks) ...memoBoxes.where(box.isAncestorOf)]) {
      final bounds = _emptyBoxBounds[member];
      if (bounds != null) _emptyBoxBounds[member] = bounds.shift(shift);
    }
  }
  Rect? _boxBounds(MemoBox box) => _liftBoxes[box] ?? _regionBounds(box, _positions) ?? _emptyBoxBounds[box];
  Rect _placeEmptyBox(double x) {
    var bounds = Rect.fromLTWH(x, 440, 260, 260);
    final occupied = [for (final box in _allRegionBoxes) ?_boxBounds(box),
      for (final id in _positions.keys) _bounds(id)];
    while (occupied.any((other) => bounds.inflate(24).overlaps(other))) {
      final bottom = occupied.where((other) => bounds.inflate(24).overlaps(other)).map((other) => other.bottom).reduce(math.max);
      bounds = bounds.shift(Offset(0, bottom + 48 - bounds.top));
    }
    return bounds;
  }
  bool _boxCollides(MemoBox moving, Rect proposed) => _allRegionBoxes.any((other) =>
    !identical(other, moving) && (!widget.blocks || (!moving.isAncestorOf(other) && !other.isAncestorOf(moving))) && _boxBounds(other) != null && memoBoxRegionsOverlap(proposed, _boxBounds(other)!, rectangular: widget.blocks));
  bool _memberCollides(String id) => _allRegionBoxes.any((box) => box.elementIds.contains(id) &&
    _boxBounds(box) != null && _boxCollides(box, _boxBounds(box)!));
  void _separateOverlappingBoxes() {
    if (widget.blocks) {
      for (var depth = 3; depth >= 1; depth--) {
        final placed = <({MemoBox box, Rect bounds})>[];
        for (final box in _allRegionBoxes.where((b) => b.depth == depth)) {
          final original = _boxBounds(box);
          if (original == null) continue;
          var bounds = original;
          final occupied = [
            ...placed.where((other) => other.box.parentName == box.parentName).map((r) => r.bounds),
            if (box.parent != null) for (final id in box.parent!.elementIds.where(_positions.containsKey)) _bounds(id),
          ];
          while (occupied.any((other) => bounds.inflate(24).overlaps(other))) {
            final bottom = occupied.where((other) => bounds.inflate(24).overlaps(other)).map((r) => r.bottom).reduce(math.max);
            bounds = bounds.shift(Offset(0, bottom + 48 - bounds.top));
          }
          _moveBox(box, bounds.topLeft - original.topLeft);
          placed.add((box: box, bounds: bounds));
        }
      }
      return;
    }
    final placed = <Rect>[];
    for (final box in _allRegionBoxes) {
      final original = _boxBounds(box);
      if (original == null) continue;
      var bounds = original;
      while (placed.any((other) => memoBoxRegionsOverlap(bounds, other, rectangular: widget.blocks))) {
        final bottom = placed.where((other) => memoBoxRegionsOverlap(bounds, other, rectangular: widget.blocks)).map((other) => other.bottom).reduce(math.max);
        bounds = bounds.shift(Offset(0, bottom + 48 - bounds.top));
      }
      final shift = bounds.topLeft - original.topLeft;
      if (shift != Offset.zero) {
        for (final id in box.elementIds.where(_positions.containsKey)) { _positions[id] = _positions[id]! + shift; }
        if (!box.elementIds.any(_positions.containsKey)) _emptyBoxBounds[box] = bounds;
      }
      placed.add(bounds);
    }
  }
  void _separateBoxes() {
    var x = 640.0;
    final assigned = <String>{};
    final top = _tagPositions.values.map((p) => tagBounds(p).bottom + 100).fold(400.0, math.max);
    var bottom = top;
    for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
      final ids = box.elementIds.where((id) => _positions.containsKey(id) && !assigned.contains(id)).toList();
      if (ids.isEmpty) continue;
      for (var i = 0; i < ids.length; i++) { _positions[ids[i]] = Offset(x + (i % 3) * 220, 600 + (i ~/ 3) * 140); }
      final bounds = _regionBounds(box, _positions)!;
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
  Future<void> _resetArrangement() async {
    final reset = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('배치 초기화'),
      content: const Text('현재 보기의 위치·크기·확대 배율을 초기화하고 다시 정리할까요? 생각 내용, 연결, 상자 분류는 유지됩니다.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('초기화'))]));
    if (reset != true || !mounted) return;
    setState(() {
      _positions.clear(); _tagPositions.clear(); _emptyBoxBounds.clear(); _liftBoxes.clear();
      _layout.sizes.clear(); _layout.viewport = null;
      _draggingId = null; _hoverBox = null; _linkFrom = null; _linkMode = false;
      _filterBox = null; _filterTag = null; _query = ''; _search.clear(); _unlinkedOnly = false;
      _centered = false; _sync();
    });
    _saveLayout(flush: true);
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
    if (widget.box != null) { moveThoughtToBox(r.id, widget.box!); }
    _changed();
  }
  void _connect(String a, String b) {
    if (a == b) return;
    elements.connect(a, [b]); _linkFrom = null; _changed();
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
    for (final box in _regionBoxes) {
      final bounds = _regionBounds(box, visiblePositions);
      if (bounds != null) regions.add((box: box, bounds: _liftBoxes[box] ?? bounds));
    }
    var emptyX = regions.map((r) => r.bounds.right + 80).fold(
      nodeRects.values.map((r) => r.right + 80).fold(640.0, math.max), math.max);
    for (final box in _regionBoxes) {
      if (_regionBounds(box, visiblePositions) != null) continue;
      regions.add((box: box, bounds: _emptyBoxBounds.putIfAbsent(box, () => _placeEmptyBox(emptyX))));
      emptyX += 340;
    }
    sceneWidth = regions.map((r) => r.bounds.right + 100).fold(sceneWidth, math.max);
    sceneHeight = regions.map((r) => r.bounds.bottom + 100).fold(sceneHeight, math.max);
    final color = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle(widget.box?.name ?? '모든 생각 보기'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const DesktopMenuAction(),
      IconButton(tooltip: '연결 모드', style: IconButton.styleFrom(backgroundColor: _linkMode ? color.primaryContainer : null, foregroundColor: _linkMode ? color.onPrimaryContainer : null), isSelected: _linkMode, onPressed: () => setState(() { _linkMode = !_linkMode; _linkFrom = null; }), icon: const Icon(Icons.link)),
      IconButton(tooltip: '생각 만들기', onPressed: _create, icon: const Icon(Icons.add)),
      if (widget.blocks) IconButton(tooltip: '메모상자 구조', icon: const Icon(Icons.account_tree_outlined), onPressed: () async {
        if (await editBoxHierarchy(context) && mounted) { _changed(); }
      }),
      IconButton(tooltip: '배치 초기화', onPressed: _resetArrangement, icon: const Icon(Icons.restart_alt)),
      IconButton(tooltip: '전체 위치 보기', onPressed: () => setState(() => _centered = false), icon: const Icon(Icons.center_focus_strong)),
      IconButton(tooltip: '사용 안내', icon: const Icon(Icons.info_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('사용 안내'),
          content: const Text('생각·태그를 드래그해 배치하세요. 생각을 누르면 수정할 수 있습니다. 연결 모드에서는 생각 두 개를 차례로 누르세요.'),
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
      Expanded(child: Stack(children: [Positioned.fill(child: LayoutBuilder(builder: (context, viewport) {
        if (!_centered) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final points = [...visiblePositions.values, ...tagPositions.values,
              for (final region in regions.map((r) => r.bounds)) ...[region.topLeft, region.bottomRight]];
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
        transformationController: _view, scaleFactor: 1000, constrained: false, minScale: .15, maxScale: MediaQuery.sizeOf(context).width >= 760 ? 12 : 8,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: RepaintBoundary(child: SizedBox(key: _sceneKey, width: sceneWidth, height: sceneHeight, child: Stack(clipBehavior: Clip.none, children: [
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds, highlighted: identical(_hoverBox, region.box), rectangular: widget.blocks,
            onDrag: (delta) => setState(() {
              final empty = _regionBounds(region.box, _positions) == null;
              final current = empty ? (_emptyBoxBounds[region.box] ?? region.bounds) : (_regionBounds(region.box, _positions) ?? region.bounds);
              var shift = Offset(math.max(delta.dx, 32 - current.left), math.max(delta.dy, 32 - current.top));
              if (_boxCollides(region.box, current.shift(shift))) {
                var low = 0.0, high = 1.0;
                for (var i = 0; i < 12; i++) {
                  final mid = (low + high) / 2;
                  if (_boxCollides(region.box, current.shift(shift * mid))) { high = mid; } else { low = mid; }
                }
                shift *= low;
              }
              if (empty) _emptyBoxBounds.putIfAbsent(region.box, () => current);
              _moveBox(region.box, shift);
              _saveLayout();
            }), onDragEnd: () => _saveLayout(flush: true)),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            nodeRects,
            {for (final r in records) r.id: {...r.connections, if (!widget.blocks) ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty || _unlinkedOnly ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final record in records) Positioned(left: _positions[record.id]!.dx - ThoughtInteraction.hitPadding, top: _positions[record.id]!.dy - ThoughtInteraction.hitPadding,
            child: ThoughtInteraction(size: _size(record.id), desktop: MediaQuery.sizeOf(context).width >= 760,
                onLift: () => setState(() {
                  _liftBoxes..clear()..addEntries(regions.where((r) => _boxMembers(r.box).contains(record.id)).map((r) => MapEntry(r.box, r.bounds)));
                }),
                onActiveChanged: (active) => setState(() { _draggingId = active ? record.id : null; if (!active) _hoverBox = null; }),
                onTap: () { if (_linkMode && _linkFrom != null) {
                  final from = _linkFrom!;
                  if (from != record.id && record.connections.contains(from)) {
                    elements.disconnect(from, record.id); _linkFrom = null; _changed();
                  } else { _connect(from, record.id); }
                }
                  else if (_linkMode) { setState(() => _linkFrom = record.id); }
                  else { showElementMetadata(context, record.text); } },
                onMove: (delta) => setState(() { final previous = _positions[record.id]!; final p = previous + delta; _positions[record.id] = Offset(math.max(32, p.dx), math.max(32, p.dy));
                  if (_liftBoxes.isEmpty && _memberCollides(record.id)) _positions[record.id] = previous;
                  final center = _bounds(record.id).center;
                  _hoverBox = regions.where((r) => !r.box.elementIds.contains(record.id) && _inside(r.bounds, center)).firstOrNull?.box;
                  _saveLayout(); }),
                onResize: (size, shift) => setState(() {
                  final oldSize = _layout.sizes[record.id], oldPosition = _positions[record.id]!;
                  _layout.sizes[record.id] = Offset(size.width, size.height);
                  final p = _positions[record.id]! + shift; _positions[record.id] = Offset(math.max(32, p.dx), math.max(32, p.dy));
                  if (_memberCollides(record.id)) {
                    _positions[record.id] = oldPosition;
                    if (oldSize == null) { _layout.sizes.remove(record.id); } else { _layout.sizes[record.id] = oldSize; }
                  }
                  _saveLayout();
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
                    moveThoughtToBox(record.id, targets.first.box);
                    _liftBoxes.clear();
                    _changed();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${targets.first.box.name}에 담았습니다.')));
                  }
                  if (detached.isNotEmpty) _changed();
                  _saveLayout(flush: true);
                }, onEnd: () { setState(() { _liftBoxes.clear(); _separateOverlappingBoxes(); _draggingId = null; _hoverBox = null; }); _saveLayout(flush: true); },
                child: Card(color: wordBackgroundColor(context, record.text),
                  shape: widget.blocks ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: _draggingId == record.id || _linkFrom == record.id ? color.primary : color.outlineVariant, width: 2)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
                    color: _linkFrom == record.id || _draggingId == record.id ? color.primary : Colors.transparent, width: _draggingId == record.id ? 3 : 2)),
                  child: SizedBox(width: _size(record.id).width - 8, height: _size(record.id).height - 8, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (AttachmentIndicators.hasAttachments(record)) Padding(padding: const EdgeInsets.only(top: 4, right: 6), child: Align(alignment: Alignment.centerRight, child: AttachmentIndicators(record: record))),
                    if (widget.blocks && record.tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 0), child: Align(alignment: Alignment.centerLeft,
                      child: Text(record.tags.map((tag) => '#$tag').join('  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)))),
                    Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Text(badgeLabel(record.text), maxLines: !_layout.sizes.containsKey(record.id) ? 3 : ((_size(record.id).height - 24 - (widget.blocks && record.tags.isNotEmpty ? 24 : 0)) / 22).floor().clamp(1, 20),
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: wordColor(context, record.text))))),
                  ])))),
            ),
          if (!widget.blocks) for (final tag in tags) Positioned(left: tagBounds(tagPositions['tag:$tag']!).left, top: tagBounds(tagPositions['tag:$tag']!).top,
            width: graphTagSize.width, height: graphTagSize.height,
            child: GestureDetector(key: ValueKey('graph-tag-$tag'), behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() {
                final p = _tagPositions['tag:$tag']! + d.delta;
                _tagPositions['tag:$tag'] = Offset(p.dx.clamp(graphTagSize.width / 2, sceneWidth - graphTagSize.width / 2), p.dy.clamp(graphTagSize.height / 2, sceneHeight - graphTagSize.height / 2)); _saveLayout();
              }),
              onPanEnd: (_) => _saveLayout(flush: true), onPanCancel: () => _saveLayout(flush: true),
              child: Tooltip(message: '#$tag', child: Chip(side: BorderSide(color: Color(hashtagColors[tag] ?? 0xFF90A4AE), width: 2.5), label: Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis),
              backgroundColor: Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: .3))))),
        ]))),
      ); })),
        if (_linkMode) Positioned(top: 8, left: 12, right: 12, child: IgnorePointer(child: Material(
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('생각 두 개를 차례로 눌러 연결하거나 해제하세요.', style: TextStyle(fontSize: 12)))))),
      ])),
      ThoughtFilters(tags: _scopeRecords.expand((r) => r.tags).toSet().toList()..sort(), scope: widget.box,
        box: _filterBox, tag: _filterTag, onChanged: _changed,
        onFilter: (box, tag) => setState(() { _filterBox = box; _filterTag = tag; _linkFrom = null; _centered = false; _sync(); })),
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

import 'package:flutter/gestures.dart';
import 'canvas_geometry.dart';
import 'memo_folder_region.dart';
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
  bool _hideTags = false;
  final _view = TransformationController();
  Timer? _saveTimer;
  late final GraphLayout _layout;
  late final TextEditingController _search;
  String? _linkFrom, _draggingId;
  final _thoughtDragOrigins = <String, Offset>{};
  MemoBox? _hoverBox;
  final _liftBoxes = <MemoBox, Rect>{};
  bool _linkMode = false, _centered = false;
  bool _selectionMode = false, _movingSelection = false;
  final _selected = <String>{};
  Offset? _selectionStart, _selectionEnd, _selectionDown;
  final _selectionPointers = <int>{};
  Set<String> _selectionBeforeGesture = {};
  final _viewportKey = GlobalKey();
  double? _pinchBase;
  Offset? _pinchAnchor;
  void _zoomCanvas(double scale, Offset globalFocal) {
    final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final focal = viewport.globalToLocal(globalFocal);
    _pinchBase ??= _view.value.getMaxScaleOnAxis() / scale;
    _pinchAnchor ??= _view.toScene(focal);
    final zoom = (_pinchBase! * scale).clamp(.15, MediaQuery.sizeOf(context).width >= 760 ? 12.0 : 8.0);
    _view.value = Matrix4.diagonal3Values(zoom, zoom, 1)..setTranslationRaw(
      focal.dx - _pinchAnchor!.dx * zoom, focal.dy - _pinchAnchor!.dy * zoom, 0);
  }
  void _endPinch() { _pinchBase = null; _pinchAnchor = null; _saveLayout(flush: true); }
  void _moveBox(MemoBox box, Offset shift) {
    for (final id in box.elementIds.where(_positions.containsKey)) { _positions[id] = _positions[id]! + shift; }
    if (_emptyBoxBounds.containsKey(box)) _emptyBoxBounds[box] = _emptyBoxBounds[box]!.shift(shift);
  }
  void _releaseBox(MemoBox box) {
    final bounds = _boxBounds(box);
    if (bounds == null) return;
    _moveBox(box, releaseBox(bounds, [for (final other in _allRegionBoxes) if (!identical(other, box)) ?_boxBounds(other)], rectangular: widget.blocks));
  }
  void _dragBox(MemoBox box, Offset delta) {
    final bounds = _boxBounds(box);
    if (bounds == null) return;
    _moveBox(box, Offset(math.max(delta.dx, 32 - bounds.left), math.max(delta.dy, 32 - bounds.top)));
    _saveLayout();
  }

  bool _routeVisible = true, _appActive = true;
  ModalRoute<dynamic>? _route;
  Size _size(String id) { final p = _layout.sizes[id]; return p == null ? (widget.blocks ? const Size(230, 120) : graphThoughtSize) : Size(p.dx, p.dy); }
  Rect _bounds(String id) => _positions[id]! & _size(id);
  @override
  void initState() {
    super.initState();
    _filterBox = widget.box;
    final base = widget.box?.layout ?? pageGraphLayout;
    _layout = widget.blocks ? base.blockLayout : base;
    _positions.addAll(_layout.positions);
    _tagPositions.addAll(_layout.tags);
    _query = _layout.query;
    _unlinkedOnly = widget.blocks && _layout.unlinkedOnly;
    _hideTags = _layout.hideTags;
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
    _layout.hideTags = _hideTags;
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
  List<ElementRecord> get _scopeRecords => elements.records.values.toList();
  List<ElementRecord> get _records => _scopeRecords.where((r) => canBrowseThought(r) &&
    (_filterBox == null || _filterBox!.elementIds.contains(r.id)) &&
    (_filterTag == null || r.tags.contains(_filterTag)) &&
    (!_unlinkedOnly || r.connections.isEmpty) &&
    (_query.isEmpty || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  void _sync() {
    final records = _records;
    final scope = _scopeRecords;
    final hadPositions = _positions.isNotEmpty;
    final newIds = scope.where((r) => !_positions.containsKey(r.id)).map((r) => r.id).toSet();
    final scopeIds = scope.map((r) => r.id).toSet();
    _layout.layers.removeWhere((id) => !scopeIds.contains(id));
    _layout.layers.addAll(scopeIds.where((id) => !_layout.layers.contains(id)).toList());
    _selected.removeWhere((id) => !scopeIds.contains(id));
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
      if (!hadPositions) _separateBoxes();
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
    if (ids.isEmpty) return null;
    if (widget.blocks) {
      final bounds = ids.map((id) => positions[id]! & _size(id)).reduce((a, b) => a.expandToInclude(b));
      return Rect.fromLTRB(bounds.left - 32, bounds.top - 52, bounds.right + 32, bounds.bottom + 32);
    }
    return memoBoxCircleBounds(ids.map((id) => positions[id]!), sizes: {for (final id in ids) positions[id]!: _size(id)});
  }
  bool _inside(Rect bounds, Offset point) => widget.blocks ? bounds.contains(point) : (point - bounds.center).distance <= bounds.width / 2;
  Iterable<MemoBox> get _regionBoxes => (_filterBox != null ? [_filterBox!] :
      memoBoxes).where((box) => !box.isUnclassified);
  Iterable<MemoBox> get _allRegionBoxes => memoBoxes.where((box) => !box.isUnclassified);
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
    !identical(other, moving) && _boxBounds(other) != null && memoBoxRegionsOverlap(proposed, _boxBounds(other)!, rectangular: widget.blocks));
  bool _memberCollides(String id) => _allRegionBoxes.any((box) => box.elementIds.contains(id) &&
    _boxBounds(box) != null && _boxCollides(box, _boxBounds(box)!));
  void _separateOverlappingBoxes() {
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
  void _resetArrangement(bool stacked) {
    setState(() {
      _positions.clear(); _tagPositions.clear(); _emptyBoxBounds.clear(); _liftBoxes.clear();
      _layout.sizes.clear(); _layout.folderPositions.clear(); _layout.viewport = null;
      _layout.stacked = stacked; _selected.clear(); _layout.layers.clear();
      _draggingId = null; _hoverBox = null; _linkFrom = null; _linkMode = false;
      _query = ''; _search.clear(); _unlinkedOnly = false;
      _centered = false; _sync();
      if (stacked) _stackThoughts();
    });
    _saveLayout(flush: true);
  }
  void _stackThoughts() {
    final remaining = _scopeRecords.map((r) => r.id).toSet();
    final groups = <List<String>>[];
    for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
      final ids = remaining.where(box.elementIds.contains).toList();
      if (ids.isNotEmpty) { groups.add(ids); remaining.removeAll(ids); }
    }
    if (remaining.isNotEmpty) groups.add(remaining.toList());
    var top = _tagPositions.values.map((p) => tagBounds(p).bottom).fold(300.0, math.max) + 100;
    for (final group in groups) {
      final width = group.map((id) => _size(id).width).fold(0.0, math.max);
      final height = group.map((id) => _size(id).height).fold(0.0, math.max);
      for (var i = 0; i < group.length; i++) {
        _positions[group[i]] = Offset(640 + (i ~/ 8) * (width + 32), top + (i % 8) * 32);
      }
      top += math.min(group.length - 1, 7) * 32 + height + 180;
    }
    _separateOverlappingBoxes();
  }
  Future<void> _createBox() async {
    final box = await createMemoBox(context);
    if (mounted && box != null) _changed();
  }
  Future<void> _editFolders() async {
    if (await editMemoFolders(context) && mounted) _changed();
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
    if (_filterBox != null) { moveThoughtToBox(r.id, _filterBox!); }
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
    final ranks = {for (var i = 0; i < _layout.layers.length; i++) _layout.layers[i]: i};
    final records = _records..sort((a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0));
    final visiblePositions = {for (final r in records) r.id: _positions[r.id]!};
    final tags = _hideTags && !widget.blocks ? <String>[] : (records.expand((r) => r.tags).toSet().toList()..sort());
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
      if (box.elementIds.any(_positions.containsKey)) continue;
      regions.add((box: box, bounds: _emptyBoxBounds.putIfAbsent(box, () => _placeEmptyBox(emptyX))));
      emptyX += 340;
    }
    sceneWidth = regions.map((r) => r.bounds.right + 100).fold(sceneWidth, math.max);
    sceneHeight = regions.map((r) => r.bounds.bottom + 100).fold(sceneHeight, math.max);
    final folders = widget.blocks ? memoFolderRegions({for (final r in regions) r.box: r.bounds}, _layout.folderPositions) : <String, Rect>{};
    if (_filterBox != null) {
      folders.removeWhere((name, _) => !regions.any((r) => r.box.folder != null && memoFolderContains(name, r.box.folder!)));
    }
    sceneWidth = folders.values.map((r) => r.right + 100).fold(sceneWidth, math.max);
    sceneHeight = folders.values.map((r) => r.bottom + 100).fold(sceneHeight, math.max);
    final color = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle(widget.box?.name ?? '모든 생각 보기'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const DesktopMenuAction(),
      IconButton(tooltip: '연결 모드', style: IconButton.styleFrom(backgroundColor: _linkMode ? color.primaryContainer : null, foregroundColor: _linkMode ? color.onPrimaryContainer : null), isSelected: _linkMode, onPressed: () => setState(() { _linkMode = !_linkMode; _linkFrom = null; _selectionMode = false; _selected.clear(); }), icon: const Icon(Icons.link)),
      PopupMenuButton<bool>(tooltip: '생각 만들기', icon: const Icon(Icons.add),
        onSelected: (box) { if (box) { _createBox(); } else { _create(); } },
        itemBuilder: (_) => const [PopupMenuItem(value: false, child: Text('생각 만들기')), PopupMenuItem(value: true, child: Text('상자 만들기'))]),
      PopupMenuButton<bool>(tooltip: '배치 초기화', icon: const Icon(Icons.restart_alt), onSelected: _resetArrangement,
        itemBuilder: (_) => const [PopupMenuItem(value: false, child: Text('펼쳐보기')), PopupMenuItem(value: true, child: Text('겹쳐보기'))]),
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
        FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero, label: Text(widget.blocks ? '연결 없음' : '해시태그 숨기기', style: const TextStyle(fontSize: 12)), selected: widget.blocks ? _unlinkedOnly : _hideTags,
          onSelected: (value) => setState(() {
            if (widget.blocks) { _unlinkedOnly = value; _centered = false; _sync(); }
            else { _hideTags = value; _saveLayout(); }
          })),
      ])),
      Expanded(child: Stack(children: [Positioned.fill(child: LayoutBuilder(builder: (context, viewport) {
        if (!_centered) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final points = [...visiblePositions.values, ...tagPositions.values,
              for (final region in [...regions.map((r) => r.bounds), ...folders.values]) ...[region.topLeft, region.bottomRight]];
            if (points.isEmpty) points.add(const Offset(1400, 1000));
            final left = points.map((p) => p.dx).reduce(math.min), right = points.map((p) => p.dx).reduce(math.max) + 170;
            final top = points.map((p) => p.dy).reduce(math.min), bottom = points.map((p) => p.dy).reduce(math.max) + 76;
            final scale = math.min(viewport.maxWidth / (right - left + 120), viewport.maxHeight / (bottom - top + 120)).clamp(.15, 1.0);
            _view.value = Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(viewport.maxWidth / 2 - (left + right) / 2 * scale,
              viewport.maxHeight / 2 - (top + bottom) / 2 * scale, 0);
          });
        }
        return InteractiveViewer(key: _viewportKey,
        panEnabled: !_selectionMode, scaleEnabled: !_selectionMode,
        onInteractionEnd: (_) => _saveLayout(flush: true),
        transformationController: _view, scaleFactor: 1000, constrained: false, minScale: .15, maxScale: MediaQuery.sizeOf(context).width >= 760 ? 12 : 8,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: RepaintBoundary(child: SizedBox(key: _sceneKey, width: sceneWidth, height: sceneHeight, child: Stack(clipBehavior: Clip.none, children: [
          for (final folder in folders.entries) MemoFolderRegion(key: ValueKey('folder-region-${folder.key}'), name: folder.key, bounds: folder.value,
            onEdit: _editFolders, onZoom: _zoomCanvas, onEnd: _endPinch, onMove: (delta) => setState(() {
              if (_pinchBase != null) return;
              final shift = Offset(math.max(delta.dx, 32 - folder.value.left), math.max(delta.dy, 32 - folder.value.top));
              for (final box in memoBoxes.where((b) => b.folder != null && memoFolderContains(folder.key, b.folder!))) {
                for (final id in box.elementIds.where(_positions.containsKey)) { _positions[id] = _positions[id]! + shift; }
                if (_emptyBoxBounds.containsKey(box)) _emptyBoxBounds[box] = _emptyBoxBounds[box]!.shift(shift);
              }
              for (final name in memoBoxFolders.where((f) => memoFolderContains(folder.key, f))) {
                if (_layout.folderPositions.containsKey(name)) _layout.folderPositions[name] = _layout.folderPositions[name]! + shift;
              }
              _saveLayout();
            })),
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds, highlighted: identical(_hoverBox, region.box), rectangular: widget.blocks,
            onDrag: (delta) => setState(() => _dragBox(region.box, delta)),
            onDragEnd: () { setState(() => _releaseBox(region.box)); _saveLayout(flush: true); }),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            nodeRects,
            {for (final r in records) r.id: {...r.connections, if (!widget.blocks && !_hideTags) ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty || _unlinkedOnly ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final record in records) Positioned(left: _positions[record.id]!.dx - ThoughtInteraction.hitPadding, top: _positions[record.id]!.dy - ThoughtInteraction.hitPadding,
            child: ThoughtInteraction(size: _size(record.id), desktop: MediaQuery.sizeOf(context).width >= 760,
                onLift: () => setState(() {
                  _liftBoxes..clear()..addEntries(regions.where((r) => r.box.elementIds.contains(record.id)).map((r) => MapEntry(r.box, r.bounds)));
                }),
                onActiveChanged: (active) => setState(() { if (active) _thoughtDragOrigins.putIfAbsent(record.id, () => _positions[record.id]!); _draggingId = active ? record.id : null; if (!active) _hoverBox = null; }),
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
                  final target = records.where((r) => r.id != record.id && _bounds(r.id).overlaps(_bounds(record.id))).lastOrNull;
                  final snap = target == null
                    ? snapThought(_bounds(record.id), records.where((r) => r.id != record.id).map((r) => _bounds(r.id)),
                        tolerance: (24 / _view.value.getMaxScaleOnAxis()).clamp(12, 48))
                    : nextStackSlot(target.id, record.id, _positions) - _positions[record.id]!;
                  final snapped = _positions[record.id]! + snap;
                  if (snapped.dx >= 32 && snapped.dy >= 32) _positions[record.id] = snapped;
                  if (target != null) {
                    _layout.layers.remove(record.id);
                    _layout.layers.add(record.id);
                    final box = memoBoxes.where((box) => !box.isUnclassified && box.elementIds.contains(target.id)).firstOrNull;
                    if (box != null) { moveThoughtToBox(record.id, box); }
                    else { for (final box in memoBoxes.where((box) => !box.isUnclassified)) { box.elementIds.remove(record.id); } }
                    _liftBoxes.clear(); _changed(); _saveLayout(flush: true);
                    return;
                  }
                  if (widget.blocks && folders.values.any((bounds) => bounds.contains(center)) &&
                      !regions.any((region) => _inside(region.bounds, center))) {
                    final origin = _thoughtDragOrigins[record.id];
                    if (origin != null) _positions[record.id] = origin;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('생각은 메모상자 안에 담아주세요. 폴더에는 직접 넣을 수 없습니다.')));
                    return;
                  }
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
                }, onEnd: () { setState(() { _thoughtDragOrigins.remove(record.id); _liftBoxes.clear(); _separateOverlappingBoxes(); _draggingId = null; _hoverBox = null; }); _saveLayout(flush: true); },
                child: Card(margin: EdgeInsets.zero, color: wordBackgroundColor(context, record.text),
                  shape: widget.blocks ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: _draggingId == record.id || _linkFrom == record.id ? color.primary : color.outlineVariant, width: 2)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
                    color: _linkFrom == record.id || _draggingId == record.id ? color.primary : color.outlineVariant, width: _draggingId == record.id ? 3 : 2)),
                  child: SizedBox(width: _size(record.id).width - 8, height: _size(record.id).height - 8, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (AttachmentIndicators.hasAttachments(record)) Padding(padding: const EdgeInsets.only(top: 4, right: 6), child: Align(alignment: Alignment.centerRight, child: AttachmentIndicators(record: record))),
                    Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Text(badgeLabel(record.text), maxLines: !_layout.sizes.containsKey(record.id) ? 3 : ((_size(record.id).height - 24 - (widget.blocks && record.tags.isNotEmpty ? 24 : 0)) / 22).floor().clamp(1, 20),
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: wordColor(context, record.text))))),
                    if ((widget.blocks || (_layout.stacked && !_hideTags)) && record.tags.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 8, 8), child: Align(alignment: Alignment.centerLeft,
                      child: Text(record.tags.map((tag) => '#$tag').join('  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)))),
                    if (_layout.stacked && (record.tags.isEmpty || (!widget.blocks && _hideTags))) const SizedBox(height: 24),
                  ])))),
            ),
          for (final region in regions) Positioned(
            left: region.bounds.center.dx - (widget.blocks ? region.bounds.width - 64 : region.bounds.width * .45) / 2,
            top: region.bounds.top + 8,
            width: widget.blocks ? region.bounds.width - 64 : region.bounds.width * .45, height: 32,
            child: GestureDetector(key: ValueKey('box-drag-header-${region.box.name}'), behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _dragBox(region.box, d.delta)),
              onPanEnd: (_) { setState(() => _releaseBox(region.box)); _saveLayout(flush: true); },
              onPanCancel: () { setState(() => _releaseBox(region.box)); _saveLayout(flush: true); })),
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
          if (_selectionMode) Positioned.fill(child: Listener(
            onPointerDown: (event) {
              if (_selectionPointers.isEmpty) {
                _selectionDown = event.localPosition;
                _selectionBeforeGesture = Set.of(_selected);
              }
              _selectionPointers.add(event.pointer);
            },
            onPointerUp: (event) { _selectionPointers.remove(event.pointer); },
            onPointerCancel: (event) { _selectionPointers.remove(event.pointer); },
            child: GestureDetector(
            key: const ValueKey('canvas-selection'), behavior: HitTestBehavior.opaque, dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) => setState(() {
              final hit = records.where((r) => RRect.fromRectAndRadius(_bounds(r.id), Radius.circular(widget.blocks ? 6 : 12)).contains(d.localPosition)).lastOrNull;
              if (hit == null) { _selected.clear(); }
              else if (!_selected.add(hit.id)) { _selected.remove(hit.id); }
            }),
            onScaleStart: (d) => setState(() {
              if (d.pointerCount > 1) return;
              _selected.removeWhere((id) => !visiblePositions.containsKey(id));
              final hit = records.where((r) => RRect.fromRectAndRadius(_bounds(r.id), Radius.circular(widget.blocks ? 6 : 12))
                .contains(_selectionDown ?? d.localFocalPoint)).lastOrNull;
              _movingSelection = hit != null;
              if (hit != null && !_selected.contains(hit.id)) { _selected..clear()..add(hit.id); }
              _selectionStart = _selectionDown ?? d.localFocalPoint; _selectionEnd = d.localFocalPoint;
              if (!_movingSelection) _selected.clear();
            }),
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount > 1) {
                _selected..clear()..addAll(_selectionBeforeGesture);
                _zoomCanvas(d.scale, d.focalPoint); _selectionStart = null; _selectionEnd = null; return;
              }
              if (_pinchBase != null || _selectionStart == null) return;
              if (_movingSelection) {
                final left = _selected.map((id) => _positions[id]!.dx).reduce(math.min);
                final top = _selected.map((id) => _positions[id]!.dy).reduce(math.min);
                final shift = Offset(math.max(d.focalPointDelta.dx / _view.value.getMaxScaleOnAxis(), 32 - left), math.max(d.focalPointDelta.dy / _view.value.getMaxScaleOnAxis(), 32 - top));
                for (final id in _selected) { _positions[id] = _positions[id]! + shift; }
              } else {
                _selectionEnd = d.localFocalPoint;
                final rect = Rect.fromPoints(_selectionStart!, _selectionEnd!);
                _selected.clear();
                for (var i = 0; i < records.length; i++) {
                  if (selectsVisibleThought(rect, _bounds(records[i].id), records.skip(i + 1).map((r) => _bounds(r.id)),
                      radius: widget.blocks ? 6 : 12)) _selected.add(records[i].id);
                }
              }
            }),
            onScaleEnd: (_) { setState(() { _selectionStart = null; _selectionEnd = null; _movingSelection = false; }); _endPinch(); },
            child: CustomPaint(painter: _SelectionPainter(
              [for (final r in records) (rect: _bounds(r.id), selected: _selected.contains(r.id))],
              !_movingSelection && _selectionStart != null && _selectionEnd != null ? Rect.fromPoints(_selectionStart!, _selectionEnd!) : null,
              color.primary, widget.blocks ? 6 : 12)),
          ))),
        ]))),
      ); })),
        if (_selected.isNotEmpty) Positioned(top: 8, left: 12, child: Material(
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(style: IconButton.styleFrom(minimumSize: const Size(32, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), tooltip: '레이어 위로', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: () {
                setState(() { moveThoughtLayers(_layout.layers, _selected, up: false); reorderStackPositions(_positions, _selected, up: true); }); _saveLayout(flush: true);
              }),
              IconButton(style: IconButton.styleFrom(minimumSize: const Size(32, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), tooltip: '레이어 아래로', icon: const Icon(Icons.arrow_downward, size: 18), onPressed: () {
                setState(() { moveThoughtLayers(_layout.layers, _selected, up: true); reorderStackPositions(_positions, _selected, up: false); }); _saveLayout(flush: true);
              }),
            ]),
            if (_selected.length > 1) TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 24), padding: const EdgeInsets.symmetric(horizontal: 6), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 11)),
              icon: const Icon(Icons.swap_vert, size: 15), label: const Text('순서 반전'), onPressed: () {
                setState(() { reverseThoughtLayers(_layout.layers, _selected); reorderStackPositions(_positions, _selected); }); _saveLayout(flush: true);
              }),
          ]),
        )),
        Positioned(top: 8, right: 0, child: Material(
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 112, child: ListTileTheme(
            data: const ListTileThemeData(horizontalTitleGap: 0, minLeadingWidth: 0),
            child: CheckboxListTile(
            title: Text(_selected.isEmpty ? '선택' : '선택 ${_selected.length}', style: const TextStyle(fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading, dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact,
            value: _selectionMode, onChanged: (value) => setState(() {
              _selectionMode = value ?? false; _selected.clear(); _selectionStart = null; _selectionEnd = null;
              if (_selectionMode) { _linkMode = false; _linkFrom = null; }
            }),
          ))),
        )),
        if (_linkMode) Positioned(top: 52, left: 12, right: 12, child: IgnorePointer(child: Material(
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('생각 두 개를 차례로 눌러 연결하거나 해제하세요.', style: TextStyle(fontSize: 12)))))),
      ])),
      ThoughtFilters(tags: _scopeRecords.expand((r) => r.tags).toSet().toList()..sort(),
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

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.selected, this.marquee, this.color, this.radius);
  final double radius;
  final List<({Rect rect, bool selected})> selected;
  final Rect? marquee;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2;
    for (var i = 0; i < selected.length; i++) {
      if (!selected[i].selected) continue;
      final visible = visibleThoughtPath(selected[i].rect,
        selected.skip(i + 1).map((item) => item.rect.inflate(.5)), radius: radius);
      canvas.save(); canvas.clipPath(visible);
      canvas.drawRRect(RRect.fromRectAndRadius(selected[i].rect.deflate(1), Radius.circular(radius)), border);
      canvas.restore();
    }
    if (marquee != null) {
      canvas.drawRect(marquee!, Paint()..color = color.withValues(alpha: .12));
      canvas.drawRect(marquee!, border);
    }
  }
  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

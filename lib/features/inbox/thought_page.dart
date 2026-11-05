import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'element_store.dart';
import 'tag_colors.dart';
import 'hashtags.dart';
import 'memo_boxes.dart';
import 'memo_box_region.dart';
import 'word_badge.dart';

/// A live workspace over the same thoughts, tags and reciprocal connections.
class ThoughtPage extends StatefulWidget {
  const ThoughtPage({super.key, required this.onChanged, this.box});
  final VoidCallback onChanged;
  final MemoBox? box;
  @override
  State<ThoughtPage> createState() => _ThoughtPageState();
}
class _ThoughtPageState extends State<ThoughtPage> {
  final _positions = <String, Offset>{};
  final _tagPositions = <String, Offset>{};
  final _pinned = <String>{};
  String _query = '';
  bool _unlinkedOnly = false;
  final _view = TransformationController();
  Timer? _timer;
  String? _selected, _linkFrom;
  bool _dragging = false, _linkMode = false, _centered = false;
  int _frames = 0;
  static const _nodeSize = Size(170, 76);
  @override
  void initState() { super.initState(); elements.addListener(_storeChanged); _sync(); }
  List<ElementRecord> get _records => elements.records.values.where((r) => widget.box == null || widget.box!.elementIds.contains(r.id)).where((r) =>
    (!_unlinkedOnly || r.connections.isEmpty) &&
    (_query.isEmpty || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  void _sync() {
    final records = _records;
    _positions.removeWhere((id, _) => !records.any((r) => r.id == id));
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
    _frames = 0;
    _timer ??= Timer.periodic(const Duration(milliseconds: 32), (_) => _relax());
  }
  void _storeChanged() { if (mounted) setState(_sync); }
  void _relax() {
    if (!mounted || _dragging) return;
    if (_frames++ > 120) { _timer?.cancel(); _timer = null; return; }
    final records = _records;
    final forces = {for (final r in records) r.id: Offset.zero};
    // Repulsion stays local so large collections remain responsive.
    for (var i = 0; i < records.length; i++) {
      for (var j = i + 1; j < records.length; j++) {
        final a = records[i].id, b = records[j].id;
        var delta = _positions[a]! - _positions[b]!;
        if (delta.distanceSquared < 1) delta = const Offset(1, 1);
        final distance = delta.distance;
        if (distance > 235) continue;
        final force = delta / distance * (500 / distance.clamp(20, 235));
        forces[a] = forces[a]! + force; forces[b] = forces[b]! - force;
      }
    }
    for (final r in records) {
      for (final id in r.connections.where(_positions.containsKey)) {
        final delta = _positions[id]! - _positions[r.id]!;
        final distance = delta.distance;
        if (distance > 1) forces[r.id] = forces[r.id]! + delta / distance * ((distance - 185) * .015);
      }
    }
    for (final box in widget.box == null ? memoBoxes : [widget.box!]) {
      final members = box.elementIds.where(_positions.containsKey).toList();
      if (members.length < 2) continue;
      final center = members.map((id) => _positions[id]!).reduce((a, b) => a + b) / members.length.toDouble();
      for (final id in members) { forces[id] = forces[id]! + (center - _positions[id]!) * .012; }
    }
    setState(() {
      for (final r in records) {
        if (_pinned.contains(r.id)) continue;
        final p = _positions[r.id]! + forces[r.id]!;
        _positions[r.id] = Offset(p.dx.clamp(30, 2770), p.dy.clamp(30, 1970));
      }
    });
  }
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
  void dispose() { _timer?.cancel(); elements.removeListener(_storeChanged); _view.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final records = _records;
    final tags = records.expand((r) => r.tags).toSet().toList()..sort();
    final tagPositions = {for (final tag in tags) 'tag:$tag': _tagPositions['tag:$tag']!};
    final regions = <({MemoBox box, Rect bounds})>[];
    for (final box in widget.box == null ? memoBoxes : [widget.box!]) {
      final bounds = memoBoxCircleBounds(box.elementIds.where(_positions.containsKey).map((id) => _positions[id]!));
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
        Expanded(child: TextField(key: const ValueKey('graph-search'),
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
            final points = [..._positions.values, ...tagPositions.values,
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
        transformationController: _view, constrained: false, minScale: .15, maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(500),
        child: SizedBox(width: 3000, height: 2200, child: Stack(clipBehavior: Clip.none, children: [
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            {for (final entry in _positions.entries) entry.key: entry.value + const Offset(85, 38), ...tagPositions},
            {for (final r in records) r.id: {...r.connections, ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty || _unlinkedOnly ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final tag in tags) Positioned(left: tagPositions['tag:$tag']!.dx - 60, top: tagPositions['tag:$tag']!.dy - 20,
            child: GestureDetector(key: ValueKey('graph-tag-$tag'),
              onPanStart: (_) => _dragging = true,
              onPanUpdate: (d) => setState(() {
                final p = _tagPositions['tag:$tag']! + d.delta / _view.value.getMaxScaleOnAxis();
                _tagPositions['tag:$tag'] = Offset(p.dx.clamp(60, 2900), p.dy.clamp(20, 2160));
              }),
              onPanEnd: (_) => _dragging = false, onPanCancel: () => _dragging = false,
              child: DragTarget<String>(onAcceptWithDetails: (d) {
              final r = records.where((r) => r.id == d.data).firstOrNull;
              if (r != null) { r.tags.add(tag); _changed(); }
            }, builder: (context, candidates, _) => Chip(label: Text('#$tag'),
              backgroundColor: Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: candidates.isEmpty ? .3 : .6))))),
          for (final record in records) Positioned(left: _positions[record.id]!.dx, top: _positions[record.id]!.dy,
            child: DragTarget<String>(onWillAcceptWithDetails: (d) => d.data != record.id,
              onAcceptWithDetails: (d) => _connect(d.data, record.id), builder: (context, candidates, _) => GestureDetector(
                onTap: () { if (_linkMode && _linkFrom != null) { _connect(_linkFrom!, record.id); }
                  else { setState(() { _selected = record.id; if (_linkMode) _linkFrom = record.id; }); } },
                onDoubleTap: () => showElementMetadata(context, record.text),
                onPanStart: (_) { _dragging = true; _pinned.add(record.id); },
                onPanUpdate: (d) => setState(() { final p = _positions[record.id]! + d.delta / _view.value.getMaxScaleOnAxis();
                  _positions[record.id] = Offset(p.dx.clamp(0, 2830), p.dy.clamp(0, 2124)); }),
                onPanEnd: (_) { _dragging = false; _sync(); }, onPanCancel: () => _dragging = false,
                child: Card(color: wordBackgroundColor(context, record.text),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
                    color: candidates.isNotEmpty || _selected == record.id ? color.primary : Colors.transparent, width: 2)),
                  child: SizedBox(width: _nodeSize.width, height: _nodeSize.height, child: Row(children: [
                    Expanded(child: Padding(padding: const EdgeInsets.all(10), child: Text(badgeLabel(record.text), maxLines: 2,
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: wordColor(context, record.text))))),
                    Draggable<String>(data: record.id, feedback: Material(child: Chip(label: Text(badgeLabel(record.text), overflow: TextOverflow.ellipsis))),
                      onDragStarted: () => _dragging = true, onDragEnd: (_) => _dragging = false,
                      child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.link, size: 20))),
                  ])))),
            )),
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
  bool shouldRepaint(covariant _Connections oldDelegate) => true;
}

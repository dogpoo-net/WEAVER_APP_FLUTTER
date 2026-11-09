import '../inbox/word_badge.dart';
import '../inbox/thought_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_attribution.dart';
import '../inbox/desktop_menu_frame.dart';
import '../inbox/element_store.dart';
import '../inbox/memo_boxes.dart';
import '../inbox/thought_filters.dart';
import '../inbox/workspace_routes.dart';

class GeologPage extends StatefulWidget {
  const GeologPage({super.key, this.box, this.viewSelector, required this.onChanged});
  final MemoBox? box;
  final Widget? viewSelector;
  final VoidCallback onChanged;
  @override
  State<GeologPage> createState() => _GeologPageState();
}
class _GeologPageState extends State<GeologPage> {
  final _map = MapController();
  String _query = '';
  MemoBox? _filterBox;
  String? _tag;
  bool _tileError = false;
  int _mapRevision = 0;
  @override
  void initState() { super.initState(); elements.addListener(_changed); }
  void _changed() { if (mounted) setState(() {}); }
  List<ElementRecord> get _scope {
    final ids = widget.box?.subtreeElementIds;
    return elements.records.values.where((r) => ids == null || ids.contains(r.id)).toList();
  }
  List<ElementRecord> get _records {
    final ids = _filterBox?.subtreeElementIds;
    return _scope.where((r) => canBrowseThought(r) && r.location != null &&
    (ids == null || ids.contains(r.id)) && (_tag == null || r.tags.contains(_tag)) &&
    (r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.contains(_query.replaceFirst('#', ''))))).toList();
  }
  LatLng _point(ElementRecord record) => LatLng(record.location!.latitude, record.location!.longitude);
  void _fit(List<ElementRecord> records) {
    if (records.isEmpty) return;
    if (records.length == 1) { _map.move(_point(records.first), 15); }
    else { _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(records.map(_point).toList()), padding: const EdgeInsets.all(48), maxZoom: 16)); }
  }
  Future<void> _open(List<ElementRecord> records) async {
    final choice = records.length == 1 ? records.first : await showModalBottomSheet<ElementRecord>(context: context,
      showDragHandle: true, builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
        for (final record in records) ListTile(title: Text(record.text, maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Text(record.tags.map((tag) => '#$tag').join(' ')), onTap: () => Navigator.pop(context, record)),
      ])));
    if (choice == null || !mounted) return;
    await showElementMetadata(context, choice.text);
    if (mounted) { widget.onChanged(); setState(() {}); }
  }
  void _tileFailed() {
    if (_tileError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !_tileError) setState(() => _tileError = true); });
  }
  @override
  void dispose() { elements.removeListener(_changed); _map.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final records = _records;
    final groups = <String, List<ElementRecord>>{};
    for (final record in records) {
      final location = record.location!;
      groups.putIfAbsent('${location.latitude.toStringAsFixed(5)},${location.longitude.toStringAsFixed(5)}', () => []).add(record);
    }
    return Scaffold(appBar: AppBar(titleSpacing: MediaQuery.sizeOf(context).width < 1000 ? 0 : null,
      leadingWidth: MediaQuery.sizeOf(context).width < 1000 ? 44 : null, title: WorkspaceTitle(widget.box?.name ?? '모든 생각 보기'), actions: [
      const DesktopMenuAction(),
      IconButton(tooltip: '위치 전체 보기', onPressed: records.isEmpty ? null : () => _fit(records), icon: const Icon(Icons.center_focus_strong)),
    ]), body: DesktopMenuBody(child: Column(children: [
      if (widget.viewSelector != null) widget.viewSelector!,
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: TextField(
        key: const ValueKey('geolog-search'),
        style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
        decoration: const InputDecoration(isDense: true, hintText: '생각·해시태그 찾기',
          prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        onChanged: (value) => setState(() => _query = value.toLowerCase().trim()))),
      if (_tileError && records.isNotEmpty) MaterialBanner(content: const Text('지도를 불러오지 못했습니다. 인터넷 연결을 확인해주세요.'), actions: [
        TextButton(onPressed: () => setState(() { _tileError = false; _mapRevision++; }), child: const Text('다시 시도')),
      ]),
      Expanded(child: records.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('위치가 기록된 생각이 없습니다.\n모바일 빠른 메모에서 위치 기록을 켜고 저장해주세요.', textAlign: TextAlign.center)))
        : FlutterMap(key: ValueKey(_mapRevision), mapController: _map,
          options: MapOptions(initialCenter: _point(records.first), initialZoom: 14, minZoom: 2, maxZoom: 19,
            initialCameraFit: records.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(records.map(_point).toList()), padding: const EdgeInsets.all(48), maxZoom: 16) : null),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'net.dogpoo.weaver', maxNativeZoom: 19,
              errorTileCallback: (_, error, stack) => _tileFailed()),
            MarkerLayer(markers: [for (final group in groups.values) Marker(point: _point(group.first), width: 132, height: 84, alignment: Alignment.topCenter, rotate: true,
              child: Semantics(button: true, label: group.first.text, child: InkWell(onTap: () => _open(group), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Material(elevation: 2, surfaceTintColor: Colors.transparent, borderRadius: BorderRadius.circular(8),
                  color: (group.every((r) => r.hiddenFromSearch) ? wordBackgroundColor(context, group.first.text) : Theme.of(context).colorScheme.primaryContainer).withValues(alpha: .60),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (group.any((record) => record.recordings.isNotEmpty || record.photos.isNotEmpty))
                      Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (group.any((record) => record.recordings.isNotEmpty))
                          Icon(Icons.volume_up_outlined, size: 13, semanticLabel: '음성 메모 포함', color: group.every((r) => r.hiddenFromSearch) ? wordColor(context, group.first.text) : Theme.of(context).colorScheme.onPrimaryContainer),
                        if (group.any((record) => record.recordings.isNotEmpty) && group.any((record) => record.photos.isNotEmpty)) const SizedBox(width: 4),
                        if (group.any((record) => record.photos.isNotEmpty))
                          Icon(Icons.image_outlined, size: 13, semanticLabel: '사진 포함', color: group.every((r) => r.hiddenFromSearch) ? wordColor(context, group.first.text) : Theme.of(context).colorScheme.onPrimaryContainer),
                      ])),
                    Text(group.length > 1 ? '${group.length}개의 생각' : group.first.text,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: group.every((r) => r.hiddenFromSearch) ? wordColor(context, group.first.text) : Theme.of(context).colorScheme.onPrimaryContainer)),
                  ]))),
                Icon(Icons.location_on, color: group.every((r) => r.hiddenFromSearch) ? Colors.grey : const Color(0xFFB52D39), size: 28,
                  shadows: const [Shadow(color: Colors.white, blurRadius: 3)]),
              ]))))]),
            const MapAttribution(),
          ])),
      ThoughtFilters(tags: _scope.expand((r) => r.tags).toSet().toList()..sort(), scope: widget.box, box: _filterBox, tag: _tag,
        onChanged: () { widget.onChanged(); setState(() {}); }, onFilter: (box, tag) => setState(() { _filterBox = box; _tag = tag; })),
    ])));
  }
}

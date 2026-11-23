import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'workspace_map_surface.dart';
import 'google_thought_map.dart';
import '../inbox/overview_tab_activity.dart';
import 'location_editor.dart';
import 'media_storage.dart';
import '../inbox/memo_comments.dart';
import '../inbox/hashtags.dart';
import 'map_marker_style.dart';
import 'dart:ui' as ui;
import 'regional_tiles.dart';
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
  const GeologPage({super.key, this.box, this.filters, this.viewSelector, required this.onChanged});
  final MemoBox? box;
  final ThoughtFilterSelection? filters;
  final Widget? viewSelector;
  final VoidCallback onChanged;
  @override
  State<GeologPage> createState() => _GeologPageState();
}
class _GeologPageState extends State<GeologPage> with RetainedOverviewTab<GeologPage> {
  final _map = MapController();
  google.GoogleMapController? _googleMap;
  bool _osmReady = false;
  String _query = '';
  bool _showTimeline = true;
  late final _filters = widget.filters ?? ThoughtFilterSelection(initialBox: widget.box);
  bool _tileError = false;
  int _mapRevision = 0;
  @override
  void initState() { super.initState(); _filters.addListener(_changed); elements.addListener(_changed); }
  void _changed() { if (mounted && tabActive) setState(() {}); }
  List<ElementRecord> get _scope => elements.records.values.toList();
  List<ElementRecord> get _records => _scope.where((r) => canBrowseThought(r) && r.location != null &&
    _filters.matches(r) &&
    (r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.contains(_query.replaceFirst('#', ''))))).toList();
  LatLng _point(ElementRecord record) => LatLng(record.location!.latitude, record.location!.longitude);
  void _fit(List<ElementRecord> records) {
    if (records.isEmpty) return;
    final controller = _googleMap;
    if (controller != null) {
      final bounds = LatLngBounds.fromPoints(records.map(_point).toList());
      final update = bounds.southWest == bounds.northEast
          ? google.CameraUpdate.newLatLngZoom(googlePoint(bounds.southWest), 15)
          : google.CameraUpdate.newLatLngBounds(
              google.LatLngBounds(
                southwest: googlePoint(bounds.southWest),
                northeast: googlePoint(bounds.northEast),
              ), 48);
      controller.moveCamera(update);
      return;
    }
    if (!_osmReady) return;
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
  Future<void> _create() async {
    final owner=MediaStorage.activeOwner;
    final draft=await showLocationEditor(context,compose:true,validate:(text){
      final content=parseTaggedInput(text).text;
      if(content.isEmpty)return '생각 내용을 입력해주세요.';
      if(elements.records.containsKey(content))return '같은 내용의 생각이 이미 있습니다. 내용을 바꿔주세요.';
      return null;
    });
    if(draft==null)return;
    Future<void> discardAttachments() async {
      for(final id in [...draft.photos.map((p)=>p.id),...draft.recordings.map((v)=>v.id)]){
        try{await MediaStorage.delete(id,owner:owner);}catch(_){}
      }
    }
    if(!mounted||owner!=MediaStorage.activeOwner){await discardAttachments();return;}
    final parsed=parseTaggedInput(draft.text);
    if(parsed.text.isEmpty || elements.records.containsKey(parsed.text)){
      await discardAttachments();if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('생각 내용을 입력해주세요. 같은 내용의 생각은 중복 생성할 수 없습니다.')));return;
    }
    final record=elements.add(draft.text)..location=draft.location..important=draft.important;
    record.photos.addAll(draft.photos);record.recordings.addAll(draft.recordings);
    final box=_filters.singleBox;
    if(box!=null&&!box.isUnclassified)moveThoughtToBox(record.id,box);
    widget.onChanged();elements.refreshVisibility();
    if(_records.any((r)=>r.id==record.id)){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_fit([record]);});}
    else {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('생각을 저장했습니다. 현재 필터에서는 숨겨져 있습니다.')));}
    try{await saveWorkspaceContent?.call();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('생각은 기기에 보관했습니다. 서버 저장에 실패했습니다. $e')));}
  }
  void _tileFailed() {
    if (_tileError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !_tileError) setState(() => _tileError = true); });
  }
  @override
  void dispose() { _filters.removeListener(_changed); if (widget.filters == null) _filters.dispose(); elements.removeListener(_changed); _map.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final records = _records;
    final chronological = [...records]..sort((a, b) {
      final time = a.location!.recordedAt.compareTo(b.location!.recordedAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    final path = chronological.map(_point).toList();
    final drawPath = _showTimeline && path.length > 1;
    const lineColor = Color(0xFFDC143C);
    final groups = <String, List<ElementRecord>>{};
    for (final record in records) {
      final location = record.location!;
      groups.putIfAbsent('${location.latitude.toStringAsFixed(5)},${location.longitude.toStringAsFixed(5)}', () => []).add(record);
    }
    return Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle(_filters.singleBox?.name ?? '전체 보기'), actions: [
      const DesktopMenuAction(),
      IconButton(tooltip:'위치에 생각 추가',onPressed:memoCommentRequest!=null&&!memoCommentsWritable?null:_create,icon:const Icon(Icons.add)),
      IconButton(tooltip: _showTimeline ? '타임라인 숨기기' : '타임라인 보이기',
        isSelected: _showTimeline, icon: const Icon(Icons.timeline),
        onPressed: () => setState(() => _showTimeline = !_showTimeline)),
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
      Expanded(child: Stack(children: [
        Positioned.fill(child: ClipRect(child: ImageFiltered(
          enabled: records.isEmpty,
          imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: IgnorePointer(ignoring: records.isEmpty, child: WorkspaceMapSurface(
          googleMap: (_) => GoogleThoughtMap(
            initialCameraPosition: google.CameraPosition(
              target: records.isEmpty ? const google.LatLng(20, 0) : googlePoint(_point(records.first)),
              zoom: records.isEmpty ? 2 : 14,
            ),
            onMapCreated: (controller) {
              _googleMap = controller;
              if (_records.length > 1) _fit(_records);
            },
            polylines: {if (drawPath) google.Polyline(
              polylineId: const google.PolylineId('timeline'), width: 2, color: lineColor,
              points: path.map(googlePoint).toList())},
            pins: [
              for (final entry in groups.entries)
                GoogleThoughtPin(
                  id: entry.key,
                  position: googlePoint(_point(entry.value.first)),
                  color: entry.value.every((r) => r.hiddenFromSearch)
                      ? Colors.grey : locationMarkerColor(entry.value.first.location!),
                  label: entry.value.length > 1
                      ? '${entry.value.length}개의 생각' : entry.value.first.text,
                  onTap: () => _open(entry.value),
                ),
            ],
          ),
          osmMap: (_) => FlutterMap(key: ValueKey('$_mapRevision-${records.isEmpty}'), mapController: _map,
          options: MapOptions(onMapReady: () {
            _googleMap = null;
            _osmReady = true;
          }, initialCenter: records.isEmpty ? const LatLng(20, 0) : _point(records.first), initialZoom: records.isEmpty ? 2 : 14, minZoom: 2, maxZoom: 19,
            initialCameraFit: records.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(records.map(_point).toList()), padding: const EdgeInsets.all(48), maxZoom: 16) : null),
          children: [
            RegionalTileLayer(onError: _tileFailed),
            if (drawPath) PolylineLayer(polylines: [
              Polyline(points: path, strokeWidth: 2, color: lineColor),
            ]),
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
                Icon(Icons.location_on, color: group.every((r) => r.hiddenFromSearch) ? Colors.grey : locationMarkerColor(group.first.location!), size: 28,
                  shadows: const [Shadow(color: Colors.white, blurRadius: 3)]),
              ]))))]),
            const MapAttribution(),
          ])))))),
        if (records.isEmpty) Positioned(top: 16, left: 16, right: 16,
          child: Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Text('위치가 기록된 생각이 없습니다.\n우측 상단 +로 생각을 남기거나 빠른 메모에서 현재 위치를 기록해주세요.', textAlign: TextAlign.center)))),
      ])),
      ThoughtFilters(tags: _scope.expand((r) => r.tags).toSet().toList()..sort(), selection: _filters,
        onChanged: () { widget.onChanged(); setState(() {}); }, onFilter: _filters.toggle),
    ])));
  }
}

import 'dart:async';
import 'overview_tab_activity.dart';
import 'workspace_search.dart';
import 'overview_tab_settings.dart';
import 'grid_columns_preference.dart';
import 'memo_comments.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'overview_collections.dart';
import 'memo_box_actions.dart';
import 'thought_settings.dart';
import '../capture/geolog_page.dart' deferred as geolog;
import 'deferred_screen.dart';
import 'desktop_menu_frame.dart';
import 'thought_filters.dart';
import 'thought_page.dart' deferred as canvas;
import 'memo_boxes.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'element_store.dart';
import 'workspace_photo_actions.dart';
import 'inbox_page.dart' show showThoughtCapture;
import '../capture/voice_transcription.dart' show fillVoiceBody;
import 'word_badge.dart';
import 'packed_badges.dart';
import 'workspace_routes.dart';
import 'workspace_storage.dart';

const thoughtViewModePreference='weaver.thoughtSquareView.v1';
// Keep the selected view available synchronously when a tab is recreated.
bool? thoughtSquareViewCache;

class ThoughtBoxView extends StatefulWidget {
  const ThoughtBoxView({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.initialBox, this.filters, this.viewSelector, this.onDeleteBoxes, this.storage});
  final Future<void> Function(Set<String>)? onDeleteBoxes;
  final WorkspaceStorage? storage;
  final ThoughtFilterSelection? filters;
  final Widget? viewSelector;
  final List<Note> notes;
  final MemoBox? initialBox;
  final VoidCallback? onChanged;
  final VoidCallback? onLayoutChanged;
  @override
  State<ThoughtBoxView> createState() => _AllThoughtsPageState();
}

class _AllThoughtsPageState extends State<ThoughtBoxView> with RouteAware, RetainedOverviewTab<ThoughtBoxView> {
  String _query = '';
  final _textWidths = <String, double>{};
  bool _photosOnly = false, _audioOnly = false;
  late final _filters = widget.filters ?? ThoughtFilterSelection(initialBox: widget.initialBox);
  MemoBox? get _filterBox => _filters.singleBox;
  int _columns = 2;
  int? _squareColumns=thoughtGridColumns.value;
  bool _square = thoughtSquareViewCache??true, _viewChosen=false;
  bool _viewReady=thoughtSquareViewCache!=null && thoughtGridColumns.loaded;
  Future<void> _viewWrite=Future.value();
  Future<void> _loadViewMode() async {
    try{await thoughtGridColumns.load();final prefs=await SharedPreferences.getInstance();if(mounted&&!_viewChosen)setState((){_squareColumns=thoughtGridColumns.value;_square=thoughtSquareViewCache??prefs.getBool(thoughtViewModePreference)??true;thoughtSquareViewCache=_square;_viewReady=true;});}catch(_){if(mounted)setState(()=>_viewReady=true);}
  }
  void _setSquareColumns(int value) {
    setState(()=>_squareColumns=value);
    thoughtGridColumns.save(value).catchError((Object error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('열 개수를 기기에 저장하지 못했습니다.')));});
  }
  void _toggleViewMode(){
    _viewChosen=true;final next=!_square;thoughtSquareViewCache=next;setState(()=>_square=next);
    _viewWrite=_viewWrite.then((_)async{final prefs=await SharedPreferences.getInstance();if(!await prefs.setBool(thoughtViewModePreference,next))throw StateError('Preference save failed');})
      .catchError((Object error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('보기 설정을 기기에 저장하지 못했습니다.')));});
  }
  int _scaleColumns = 2;
  void _changed() { setState(() {}); widget.onChanged?.call(); }
  Future<void> _createThought() async {
    final record = await showThoughtCapture(context, widget.storage);
    if (record == null || !mounted) return;
    final box = _filterBox;
    if (box != null) moveThoughtToBox(record.id, box);
    _changed();
    fillVoiceBody(record);
    try {
      await saveWorkspaceContent?.call();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('생각을 동기화하지 못했습니다. $error')),
      );
    }
  }

  ModalRoute<dynamic>? _route;
  void _refresh() { if (mounted && tabActive) setState(() {}); }
  @override
  void initState() { super.initState(); _loadViewMode(); _filters.addListener(_refresh); elements.addListener(_refresh); memoCommentCounts.addListener(_refresh); }
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
    memoCommentCounts.removeListener(_refresh);
    super.dispose();
  }
  Widget _badge(String word, bool desktop) => WordBadge(word: word, compact: true, fullText: true, square: _square, query: _query,
    onTap: () => showElementMetadata(context, word, onSaved: _refresh));
  Widget _tile(ElementRecord record, bool desktop, {double width = 280}) {
    final tile = SizedBox(key: ValueKey('thought-${record.id}'), width: width, height: _square ? width : null, child: _badge(record.text, desktop));
    final previewWidth = math.min(width, 180.0);
    final feedback = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: previewWidth,
        height: _square ? previewWidth : null,
        child: _badge(record.text, desktop),
      ),
    );
    if (desktop) { return Draggable<MemoDrag>(key:ValueKey(record.id), data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile); }
    return LongPressDraggable<MemoDrag>(key:ValueKey(record.id), data: MemoDrag(record.id), feedback: feedback,
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile);
  }
  @override
  Widget build(BuildContext context) {
    if(!_viewReady)return const SizedBox.shrink();
    final allRecords = elements.records.values.toList();
    final tags = {...allRecords.expand((record) => record.tags)}.toList()..sort();
    final query = _query.toLowerCase();
    final tagQuery = query.startsWith('#') ? query.substring(1) : query;
    final records = allRecords.where((record) => _filters.matches(record) &&
      canBrowseThought(record) &&
      ((!_photosOnly && !_audioOnly) ||
        (_photosOnly && record.photos.isNotEmpty) ||
        (_audioOnly && record.recordings.isNotEmpty)) &&
      (query.isEmpty || record.indexLabel.toLowerCase().contains(query) ||
        record.text.toLowerCase().contains(query) ||
        record.tags.any((tag) => tag.toLowerCase().contains(tagQuery))))
      .toList()..sort(compareThoughtPriority);
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    final countLabel = _query.isEmpty && _filters.isEmpty ? '생각 ${records.length}개' : '생각 ${records.length}개 / 전체 ${allRecords.length}개';
    final grid = LayoutBuilder(builder: (context, bounds) {
      final available = math.min(1000.0, math.max(0.0, bounds.maxWidth - 24));
      if(_square){
        final defaultColumns = MediaQuery.sizeOf(context).shortestSide >= 600 || desktop ? 6 : 2;
        final columns=(_squareColumns ?? defaultColumns).clamp(1, math.max(1,(available/80).floor())).toInt();
        return Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:IconButtonTheme(data:IconButtonThemeData(style:IconButton.styleFrom(minimumSize:const Size(36,36),padding:EdgeInsets.zero,tapTargetSize:MaterialTapTargetSize.shrinkWrap)),child:Row(children:[Expanded(child:OverviewItemCount(countLabel, inset: 0)),
          IconButton(tooltip:'확대',onPressed:columns>1?()=>_setSquareColumns(columns-1):null,icon:const Icon(Icons.zoom_in)),
          Text('$columns열'),IconButton(tooltip:'축소',onPressed:columns<math.max(1,(available/80).floor())?()=>_setSquareColumns(columns+1):null,icon:const Icon(Icons.zoom_out)),
        ]))),Expanded(child:records.isEmpty?Center(child:Text(allRecords.isEmpty?'아직 생각이 없어요.':_filterBox!=null&&_query.isEmpty?'이 상자에 담긴 메모가 없어요.':'일치하는 생각이 없어요.')):GridView.builder(key:const ValueKey('thought-square-grid'),padding:const EdgeInsets.fromLTRB(12,8,12,12),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:columns,crossAxisSpacing:8,mainAxisSpacing:8),itemCount:records.length,itemBuilder:(_,i)=>_tile(records[i],desktop,width:(available-8*(columns-1))/columns)))]);
      }
      final maxWidth = desktop ? math.min(480.0, available)
        : (available * 2 / _columns).clamp(math.min(48.0, available), available);
      // Measurements depend on text and typography, not on sync or comments.
      if (_textWidths.length > math.max(records.length * 2, 512)) {
        _textWidths.removeWhere((text, _) => !elements.records.containsKey(text));
      }
      final items = <({ElementRecord record, double width})>[];
      for (final record in records) {
        final textWidth = _textWidths.putIfAbsent(record.text, () {
          final painter = TextPainter(text: TextSpan(text: record.text,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
            textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
          final width = painter.width; painter.dispose(); return width;
        });
        final iconCount = (record.photos.isNotEmpty ? 1 : 0) + (record.recordings.isNotEmpty ? 1 : 0) + (record.location != null ? 1 : 0) + (record.important ? 1 : 0);
        final count=memoCommentCounts.value[record.id]??0;
        final width = (textWidth + 8 + (iconCount>0||count>0?17:0)).clamp(math.min(16.0, maxWidth), maxWidth).toDouble();
        items.add((record: record, width: width));
      }
      return GestureDetector(
        onScaleStart: desktop ? null : (_) => _scaleColumns = _columns,
        onScaleUpdate: desktop ? null : (details) {
          if (details.pointerCount < 2) return;
          final next = (_scaleColumns / details.scale).round().clamp(1, 6);
          if (next != _columns) setState(() => _columns = next);
        },
        child: ListView.builder(key: const ValueKey('all-thoughts-grid'), scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          itemCount: 1 + math.max(1, (items.length / 32).ceil()),
          itemBuilder: (context, index) {
            Widget child;
            if (index == 0) {
              child = IconButtonTheme(data:IconButtonThemeData(style:IconButton.styleFrom(minimumSize:const Size(36,36),padding:EdgeInsets.zero,tapTargetSize:MaterialTapTargetSize.shrinkWrap)),child:Row(children: [
                Expanded(child: OverviewItemCount(countLabel, inset: 0)),
                if (!desktop) ...[
                  IconButton(tooltip: '확대', onPressed: _columns > 1 ? () => setState(() => _columns--) : null, icon: const Icon(Icons.zoom_in)),
                  Text('${(200 / _columns).round()}%', style: Theme.of(context).textTheme.bodyMedium),
                  IconButton(tooltip: '축소', onPressed: _columns < 6 ? () => setState(() => _columns++) : null, icon: const Icon(Icons.zoom_out)),
                ],
              ]));
            } else if (items.isEmpty) {
              child = Padding(padding: const EdgeInsets.all(40), child: Text(allRecords.isEmpty ? '아직 생각이 없어요.' : _filterBox != null && _query.isEmpty ? '이 상자에 담긴 메모가 없어요.' : '일치하는 생각이 없어요.'));
            } else {
              child = Padding(padding: const EdgeInsets.only(bottom: 6), child: PackedBadges(children: [for (final item in items.skip((index - 1) * 32).take(32)) _tile(item.record, desktop, width: item.width)]));
            }
            return index==0?child:Center(child: SizedBox(width: available, child: child));
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
      if(widget.storage?.canvasWritable??true)MemoBoxActions(onCreateThought:_createThought, onCreatePhoto: () => createWorkspacePhoto(context, widget.storage, box: _filterBox, onChanged: _changed), onCreate: () async { final box = await createMemoBox(context); if (mounted && box != null) _changed(); }),
      IconButton(tooltip: _square ? '바둑판식 보기 · 행으로 전환' : '행으로 보기 · 바둑판으로 전환', icon: Icon(_square ? Icons.grid_view : Icons.view_stream), onPressed:_toggleViewMode),
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

enum ThoughtView { search, documents, boxes, page, photos, audio, geolog }
const activeThoughtViews = [ThoughtView.search, ThoughtView.documents, ThoughtView.boxes, ThoughtView.page, ThoughtView.photos, ThoughtView.audio, ThoughtView.geolog];

class AllThoughtsPage extends StatefulWidget {
  const AllThoughtsPage({super.key, required this.notes, this.onChanged, this.onLayoutChanged, this.onSave, this.storage, this.onDocument, this.onCreateDocument, this.onRefresh, this.onReloadResource, this.onDeleteBoxes, this.initialBox, this.initialView});
  final List<Note> notes;
  final VoidCallback? onChanged, onLayoutChanged;
  final WorkspaceStorage? storage;
  final Future<void> Function(Note)? onDocument;
  final Future<void> Function()? onCreateDocument;
  final Future<void> Function()? onRefresh;
  final Future<void> Function(String)? onReloadResource;
  final Future<void> Function(Set<String>)? onDeleteBoxes;
  final Future<void> Function()? onSave;
  final MemoBox? initialBox;
  final ThoughtView? initialView;
  @override
  State<AllThoughtsPage> createState() => _ThoughtViewsState();
}
class _ThoughtViewsState extends State<AllThoughtsPage> with SingleTickerProviderStateMixin {
  void _liveChanged(){if(mounted)setState((){});}
  bool _loading = false;
  Timer? _tabReload;

  void _selectTab(ThoughtView view) {
    if (_view == view) return;
    setState(() => _view = view);
    _rememberTab();
    _tabPosition.animateTo(
      _visibleTabs.indexOf(view).toDouble(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
    );
    _tabReload?.cancel();
    _tabReload = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _reload();
    });
  }
  void _searchTag(String tag) {
    _searchController.text = '#$tag';
    if (_hiddenTabs.contains(ThoughtView.search)) {
      setState(() => _hiddenTabs.remove(ThoughtView.search));
    }
    _selectTab(ThoughtView.search);
  }
  Future<void> _reload() async {
    if (_loading || widget.onRefresh == null) return;
    _loading = true;
    // Keep the mounted collection and its scroll/filter state while reading deltas.
    try { await widget.onRefresh!(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('서버 변경을 확인하지 못했습니다. 기기의 자료를 표시합니다. $e'))); }
    finally { if (mounted) { final names = _filters.boxes.map((b) => b.name).toSet(); _filters.boxes..clear()..addAll(memoBoxes.where((b) => names.contains(b.name))); setState(() { _loading = false; }); } }
  }
  final _searchController = TextEditingController();
  List<ThoughtView> _tabOrder = List.of(activeThoughtViews);
  final _hiddenTabs = <ThoughtView>{};
  bool _tabsReady = false;
  List<ThoughtView> get _visibleTabs => _tabOrder.where((v)=>!_hiddenTabs.contains(v)).toList();
  Future<void> _loadTabs() async {
    final settings = await loadOverviewTabs(activeThoughtViews.map((v)=>v.name).toList());
    String? remembered;
    try { remembered = (await SharedPreferences.getInstance()).getString('weaver.overviewLastTab.v1'); } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (widget.initialView == null && widget.initialBox == null) {
        for (final view in activeThoughtViews) { if (view.name == remembered) _view = view; }
      }
      _tabOrder = settings.order.map((name)=>ThoughtView.values.byName(name)).toList();
      _hiddenTabs.addAll(settings.hidden.map((name)=>ThoughtView.values.byName(name)));
      if (!_visibleTabs.contains(_view)) _view = _visibleTabs.first;
      _tabPosition.value = _visibleTabs.indexOf(_view).toDouble();
      _tabsReady = true;
    });
  }
  Future<void> _configureTabs() async {
    final next = await showOverviewTabSettings(context, OverviewTabs(_tabOrder.map((v)=>v.name).toList(), _hiddenTabs.map((v)=>v.name).toSet()), thoughtViewLabel);
    if (next == null || !mounted) return;
    try { await saveOverviewTabs(next); } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('탭 설정을 저장하지 못했습니다.')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _tabOrder = next.order.map((name)=>ThoughtView.values.byName(name)).toList();
      _hiddenTabs..clear()..addAll(next.hidden.map((name)=>ThoughtView.values.byName(name)));
      if (!_visibleTabs.contains(_view)) _view = _visibleTabs.first;
      _tabPosition.value = _visibleTabs.indexOf(_view).toDouble();
    });
  }
  Future<void> _tabWrite = Future.value();
  void _rememberTab() {
    final name = _view.name;
    _tabWrite = _tabWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weaver.overviewLastTab.v1', name);
    }).catchError((Object _) {});
  }
  late final AnimationController _tabPosition;
  late final _filters = ThoughtFilterSelection(initialBox: widget.initialBox);
  @override
  void initState() {
    super.initState();
    ensureUnclassifiedBox();
    widget.storage?.liveChanges.addListener(_liveChanged);
    afterWorkspaceRouteEntrance(context, () { if (mounted) _reload(); });
    _tabPosition=AnimationController(vsync:this,upperBound:activeThoughtViews.length-1.0,value:activeThoughtViews.indexOf(_view).toDouble());
    _loadTabs();
  }
  @override
  void dispose() { widget.storage?.liveChanges.removeListener(_liveChanged); _filters.dispose(); _tabReload?.cancel(); _tabPosition.dispose(); _searchController.dispose(); super.dispose(); }
  int _cacheEpoch = 0;
  final _cachedTabs = <ThoughtView, Widget>{};
  final _recentTabs = <ThoughtView>[];
  @override void didUpdateWidget(covariant AllThoughtsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.storage, widget.storage)) {
      oldWidget.storage?.liveChanges.removeListener(_liveChanged);
      widget.storage?.liveChanges.addListener(_liveChanged);
      _cachedTabs.clear(); _recentTabs.clear(); _cacheEpoch++;
      _searchController.clear(); _filters.boxes.clear(); _filters.tags.clear();
      if(widget.initialBox!=null)_filters.boxes.add(widget.initialBox!);
    }
  }
  late ThoughtView _view = widget.initialView ?? ThoughtView.boxes;
  @override
  Widget build(BuildContext context) {
    if (!_tabsReady) return const DesktopMenuFrame(child:Scaffold(appBar:null,body:DesktopMenuBody(child:SizedBox.shrink())));
    final activeBox = widget.initialBox == null ? null : memoBoxes.where((b) => b.name == widget.initialBox!.name).firstOrNull;
    final selector = SingleChildScrollView(
      key: const PageStorageKey('overview-tabs'), scrollDirection: Axis.horizontal,
      child: SizedBox(height:40, width:(_visibleTabs.length+1)*104, child:Stack(children:[
        AnimatedBuilder(animation:_tabPosition,builder:(context,_)=>!OverviewTabActivity.of(context)?const SizedBox.shrink():Positioned(
          left:_tabPosition.value*104,top:0,bottom:0,width:104,
          child:ColoredBox(key:const ValueKey('thought-tab-highlight'),color:Theme.of(context).colorScheme.secondaryContainer))),
        Row(children:[
          for(final view in _visibleTabs) SizedBox(width:104,height:40,child:Semantics(
            selected:view==_view,child:TextButton(
              style:TextButton.styleFrom(shape:const RoundedRectangleBorder()),
              onPressed: () => _selectTab(view),
              child:Text(thoughtViewLabel(view.name))))),
          SizedBox(width:104,height:40,child:TextButton(key:const ValueKey('overview-tab-settings'),
            style:TextButton.styleFrom(shape:const RoundedRectangleBorder()),onPressed:_configureTabs,
            child:const Tooltip(message:'탭 설정',child:Icon(Icons.settings_outlined,size:20)))),
        ]),
      ])),
    );
    _cachedTabs.removeWhere((view, _) => !_visibleTabs.contains(view));
    _recentTabs.removeWhere((view) => !_cachedTabs.containsKey(view));
    _recentTabs.remove(_view); _recentTabs.add(_view);
    _cachedTabs[_view] = _buildTab(_view, selector, activeBox);
    final capacity = MediaQuery.sizeOf(context).shortestSide < 600 ? 3 : activeThoughtViews.length;
    while (_cachedTabs.length > capacity) { _cachedTabs.remove(_recentTabs.removeAt(0)); }
    return Stack(fit:StackFit.expand,children:[
      for(final view in activeThoughtViews) if(_cachedTabs.containsKey(view))
        OverviewTabActivity(key:ValueKey('retained-$_cacheEpoch-${widget.storage?.owner}-${view.name}'),active:view==_view,
          child:Offstage(offstage:view!=_view,child:TickerMode(enabled:view==_view,
            child:PrimaryScrollController.none(child:ExcludeFocus(excluding:view!=_view,child:HeroMode(enabled:view==_view,child:_cachedTabs[view]!)))))),
    ]);
  }
  Widget _buildTab(ThoughtView view, Widget selector, MemoBox? activeBox) {
    if(view==ThoughtView.search)return DesktopMenuFrame(child:WorkspaceSearch(notes:widget.notes,selector:selector,controller:_searchController,onDocument:widget.onDocument,
      onBox: (box) {
        _filters.openBox(box);
        if (_hiddenTabs.contains(ThoughtView.page)) {
          setState(() => _hiddenTabs.remove(ThoughtView.page));
        }
        _selectTab(ThoughtView.page);
      }));
    if(view==ThoughtView.documents)return DesktopMenuFrame(child:DocumentCollection(notes:widget.notes,selector:selector,storage:widget.storage,onOpen:widget.onDocument,onCreate:widget.onCreateDocument));
    if(view==ThoughtView.photos || view==ThoughtView.audio)return DesktopMenuFrame(child:AttachmentCollection(key:ValueKey(view),audio:view==ThoughtView.audio,selector:selector,filters:_filters,storage:widget.storage,onChanged:widget.onChanged));
    if (view == ThoughtView.geolog) { return DeferredScreen(
      load: geolog.loadLibrary,
      selector: selector,
      builder: (_) => DesktopMenuFrame(child: geolog.GeologPage(
        filters: _filters,
        box: activeBox,
        viewSelector: selector,
        onChanged: () => widget.onChanged?.call(),
      )),
    ); }
    if (view == ThoughtView.boxes) { return DesktopMenuFrame(child: ThoughtBoxView(storage:widget.storage,filters: _filters, notes: widget.notes, initialBox: activeBox,
      onChanged: widget.onChanged, onLayoutChanged: widget.onLayoutChanged, viewSelector: selector, onDeleteBoxes: widget.onDeleteBoxes)); }
    // A menu box selects a filter, not a different canvas. All entry routes
    // must read/write the workspace layout so tab changes preserve placement.
    return DeferredScreen(
      load: canvas.loadLibrary,
      selector: selector,
      builder: (_) => DesktopMenuFrame(child: canvas.ThoughtPage(
        filters: _filters,
        key: ValueKey(view),
        onChanged: () => widget.onChanged?.call(),
        onLayoutChanged: widget.onLayoutChanged,
        onSave: widget.onSave,
        storage: widget.storage,
        viewSelector: selector,
        onDeleteBoxes: widget.onDeleteBoxes,
        onSearchTag: _searchTag,
      )),
    );
  }
}

String thoughtViewLabel(String name) => switch (ThoughtView.values.byName(name)) { ThoughtView.search=>'검색', ThoughtView.documents=>'문서', ThoughtView.boxes=>'생각', ThoughtView.page=>'메모상자', ThoughtView.photos=>'사진', ThoughtView.audio=>'음성', ThoughtView.geolog=>'지오로그' };

import 'workspace_photo.dart';
import 'workspace_photo_actions.dart';
import 'overview_collections.dart' show StoredThumbnail;
import 'overview_tab_activity.dart';
import 'memo_comment_count.dart';
import 'canvas_link_text.dart';
import 'canvas_stack_edit.dart';
import 'canvas_occlusion.dart';
import 'memo_comments.dart';
import 'package:flutter/services.dart';
import 'workspace_storage.dart';
import 'save_shortcuts.dart';
import 'memo_box_actions.dart';
import 'thought_label.dart';
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
import 'inbox_page.dart' show showThoughtCapture;
import '../capture/voice_transcription.dart' show fillVoiceBody;
import 'tag_colors.dart';
import 'memo_boxes.dart';
import 'memo_box_region.dart';
import 'word_badge.dart';
import 'graph_layout.dart';
import 'thought_interaction.dart';
import 'workspace_routes.dart';
import 'graph_arrangement.dart';

typedef _StackInsertion = ({
  String moving,
  String target,
  List<String> members,
  Map<String, Offset> positions,
  double top,
  double left,
  double width,
});

// History keeps only changed geometry and container assignments.
class _CanvasState {
  final layout = GraphLayout();
  final emptyBoxes = <MemoBox, Rect>{};
  final thoughtBoxes = <String, MemoBox>{};
  final boxFolders = <MemoBox, String>{};
  final folderParents = <String, String>{};

  bool keepChangesAgainst(_CanvasState after) {
    bool retain<K, V>(Map<K, V> before, Map<K, V> next) {
      final unchanged = before.keys.where((key) => before[key] == next[key]).toList();
      for (final key in unchanged) {
        before.remove(key);
        next.remove(key);
      }
      return before.isNotEmpty || next.isNotEmpty;
    }

    final changes = [
      retain(layout.positions, after.layout.positions),
      retain(layout.sizes, after.layout.sizes),
      retain(layout.tags, after.layout.tags),
      retain(layout.folderPositions, after.layout.folderPositions),
      retain(layout.containerBounds, after.layout.containerBounds),
      retain(layout.stackGroups, after.layout.stackGroups),
      retain(emptyBoxes, after.emptyBoxes),
      retain(thoughtBoxes, after.thoughtBoxes),
      retain(boxFolders, after.boxFolders),
      retain(folderParents, after.folderParents),
      layout.stacked != after.layout.stacked,
    ];
    if (listEquals(layout.layers, after.layout.layers)) {
      layout.layers.clear();
      after.layout.layers.clear();
    } else {
      changes.add(true);
    }
    return changes.contains(true);
  }
}

/// A live workspace over the same thoughts and tags.
class ThoughtPage extends StatefulWidget {
  const ThoughtPage({super.key, required this.onChanged, this.onLayoutChanged, this.onSave, this.storage, this.box, this.viewSelector, this.filters, this.onDeleteBoxes, this.onSearchTag});
  final Future<void> Function(Set<String>)? onDeleteBoxes;
  final VoidCallback onChanged;
  final VoidCallback? onLayoutChanged;
  final ValueChanged<String>? onSearchTag;
  final Future<void> Function()? onSave;
  final WorkspaceStorage? storage;
  final MemoBox? box;
  final ThoughtFilterSelection? filters;
  final Widget? viewSelector;
  @override
  State<ThoughtPage> createState() => _ThoughtPageState();
}
class _ThoughtPageState extends State<ThoughtPage> with WidgetsBindingObserver, RouteAware, RetainedOverviewTab<ThoughtPage> {
  final _sceneKey = GlobalKey();
  final _emptyBoxBounds = <MemoBox, Rect>{};
  final _positions = <String, Offset>{};
  final _tagPositions = <String, Offset>{};
  String _query = '';
  late final _filters = widget.filters ?? ThoughtFilterSelection(initialBox: widget.box);
  MemoBox? get _filterBox => _filters.singleBox;
  void _filterChanged() { if (mounted && tabActive) setState(() { _centered = false; _sync(); }); }
  bool _hideTags = false;
  final _view = TransformationController();
  Timer? _saveTimer;
  late final GraphLayout _layout;
  GraphLayout get _targetLayout{final base=widget.box?.layout??pageGraphLayout;return base.blockLayout;}
  late GraphLayout _publishedLayout;
  bool _remoteLayoutPending = false;
  static const _historyLimit = 50;
  final _undo = <({_CanvasState before, _CanvasState after})>[];
  final _redo = <({_CanvasState before, _CanvasState after})>[];
  _CanvasState? _gestureBefore;
  final _searchFocus = FocusNode();

  final _activeCanvasPointers=<int>{};
  String get _resource=>'canvas:boxes';
  bool get _canEdit=>widget.storage?.canvasWritable??true;
  late final TextEditingController _search;
  _StackInsertion? _stackPreview;

  _StackInsertion? _findStackInsertion(String moving, List<ElementRecord> records) {
    if (workspacePhotos.containsKey(moving)) return null;
    final card = _bounds(moving);
    final positions = Map<String, Offset>.of(_positions);
    final origin = _thoughtDragOrigins[moving];
    if (origin != null) {
      final before = {...positions, moving: origin};
      final original = alignedStackMembers(moving, before, groups: _layout.stackGroups).toList()
        ..sort((a, b) => before[a]!.dy.compareTo(before[b]!.dy));
      if (original.length > 1 && (card.left - origin.dx).abs() < _size(moving).width / 2) {
        final slots = [for (final id in original) before[id]!];
        if (card.top >= slots.first.dy - 32 && card.top <= slots.last.dy + 32) {
          var nearest = 0;
          for (var i = 1; i < slots.length; i++) {
            if ((slots[i].dy - card.top).abs() < (slots[nearest].dy - card.top).abs()) nearest = i;
          }
          original.remove(moving);
          final neighbor = original[nearest.clamp(0, original.length - 1)];
          original.insert(nearest, moving);
          for (var i = 0; i < slots.length; i++) { positions[original[i]] = slots[i]; }
          return (moving: moving, target: neighbor, members: original, positions: positions,
            left: slots[nearest].dx, top: slots[nearest].dy, width: _size(moving).width);
        }
      }
      closeVacatedStackSlots(positions, {...positions, moving: origin}, {moving},
        groups: _layout.stackGroups);
    }
    positions.remove(moving);
    final visible = records.map((record) => record.id).where((id) => !workspacePhotos.containsKey(id));
    String? target;
    var bestDistance = double.infinity;
    for (final id in visible) {
      if (id == moving) continue;
      final position = _positions[id];
      if (position == null) continue;
      final bounds = position & _size(id);
      if (card.left >= bounds.right || card.right <= bounds.left ||
          card.top < bounds.top - 32 || card.top >= bounds.bottom) continue;
      final distance = (card.top - bounds.top).abs();
      if (distance < bestDistance || (distance == bestDistance && id.compareTo(target!) < 0)) {
        bestDistance = distance;
        target = id;
      }
    }
    if (target == null) return null;

    final members = alignedStackMembers(target, positions, groups: _layout.stackGroups)
        .toList()..sort((a, b) => positions[a]!.dy.compareTo(positions[b]!.dy));
    final first = positions[members.first]!;
    const step = 32.0;
    final top = positions[members.last]!.dy + step;
    positions[moving] = Offset(first.dx, top);
    final stackShift = positions[moving]! - _positions[moving]!;
    if ((_limitThoughtDrag({moving}, stackShift) - stackShift).distance > .001) return null;
    members.add(moving);
    return (moving: moving, target: target, members: members, positions: positions,
      left: first.dx, top: top, width: _size(target).width);
  }

  void _insertStackLayer(List<String> layers, _StackInsertion insertion) {
    final moving = insertion.moving;
    final index = insertion.members.indexOf(moving);
    final next = insertion.members.skip(index + 1).where(layers.contains).firstOrNull;
    final previous = insertion.members.take(index).where(layers.contains).lastOrNull;
    layers.remove(moving);
    final slot = next != null ? layers.indexOf(next)
        : previous != null ? layers.indexOf(previous) + 1 : layers.length;
    layers.insert(slot, moving);
  }

  String? _draggingId;
  final _dropHighlights = <String>{};
  final _thoughtDragOrigins = <String, Offset>{};
  String? _linkHoverSource, _linkHoverTarget;
  void _hoverMemoLink(String source, String? link) {
    if (!mounted) return;
    if (link == null && _linkHoverSource != source) return;
    final target = link != null && link.startsWith('label:') ? link.substring(6) : null;
    if (_linkHoverSource == source && _linkHoverTarget == target) return;
    setState(() { _linkHoverSource = link == null ? null : source; _linkHoverTarget = target; });
  }
  MemoBox? _hoverBox;
  final _liftBoxes = <MemoBox, Rect>{};
  bool _centered = false;
  bool _detailOpen = false;
  String? _liftedThought;
  bool _selectionPinned = false, _movingSelection = false, _ctrlPressed = false, _shiftPressed = false;
  bool get _selectionMode => _selectionPinned || _ctrlPressed;
  bool get _selectionChecked => _selectionMode || _selected.isNotEmpty;
  bool get _rangeSelection => _selectionMode || _shiftPressed || _selectionStart != null;
  bool _controlSelection(KeyEvent event) {
    if(!tabActive || !_routeVisible)return false;
    if (_canEdit && !_searchFocus.hasFocus &&
        _activeCanvasPointers.isEmpty && event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ && _undo.isNotEmpty) {
        _stepHistory(redo: false);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY && _redo.isNotEmpty) {
        _stepHistory(redo: true);
        return true;
      }
    }
    if (mounted && tabActive && _routeVisible && event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        (_selectionMode || _selected.isNotEmpty || _selectionStart != null)) {
      setState(() {
        if (_movingSelection) {
          for (final e in _selectionDragOrigins.entries) { _setSelectionPoint(e.key, e.value); }
        }
        _clearSelectionLift(); _selected.clear(); _selectionPinned=false; _ctrlPressed=false; _shiftPressed=false;
        _rangeAnchor=null; _rangeAnchorPoint=null; _selectionBeforeGesture.clear();
        _selectionPointers.clear(); _selectionZoomBase=null; _selectionZoomDistance=null;
        _selectionZoomAnchor=null; _selectionPinched=false;
      });
      _saveLayout(flush:true);
      return true;
    }
    final pressed = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (mounted && (pressed != _ctrlPressed || shift != _shiftPressed)) setState(() { _ctrlPressed = pressed; _shiftPressed = shift; });
    return false;
  }
  final _selected = <String>{};
  Offset? _canvasTapDown;
  int? _canvasTapPointer;
  String? _rangeAnchor;
  Offset? _selectionStart, _selectionEnd, _selectionDown, _selectionGlobalDown;
  final _selectionDragOrigins = <String, Offset>{};
  final _selectionPointers = <int, Offset>{};
  double? _selectionZoomBase, _selectionZoomDistance;
  Offset? _selectionZoomAnchor;
  bool _selectionPinched = false;
  void _updateSelectionZoom() {
    if (_selectionPointers.length < 2) return;
    final points = _selectionPointers.values.take(2).toList();
    final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final focal = viewport.globalToLocal((points[0] + points[1]) / 2);
    final distance = (points[0] - points[1]).distance;
    _selectionZoomDistance ??= math.max(1, distance);
    _selectionZoomBase ??= _view.value.storage[0].abs();
    _selectionZoomAnchor ??= _view.toScene(focal);
    final zoom = (_selectionZoomBase! * distance / _selectionZoomDistance!).clamp(.15, MediaQuery.sizeOf(context).width >= 760 ? 12.0 : 8.0);
    _view.value = Matrix4.diagonal3Values(zoom, zoom, zoom)..setTranslationRaw(
      focal.dx - _selectionZoomAnchor!.dx * zoom, focal.dy - _selectionZoomAnchor!.dy * zoom, 0);
    _selectionPinched = true;
  }
  void _removeSelectionPointer(int pointer) {
    _selectionPointers.remove(pointer);
    if (_selectionPointers.length < 2) { _selectionZoomBase = null; _selectionZoomDistance = null; _selectionZoomAnchor = null; }
    if (_selectionPointers.isEmpty) _selectionPinched = false;
  }
  Set<String> _selectionBeforeGesture = {};
  final _viewportKey = GlobalKey();
  double? _pinchBase;
  Offset? _pinchAnchor;
  void _zoomCanvas(double scale, Offset globalFocal) {
    final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final focal = viewport.globalToLocal(globalFocal);
    _pinchBase ??= _view.value.storage[0].abs() / scale;
    _pinchAnchor ??= _view.toScene(focal);
    final zoom = (_pinchBase! * scale).clamp(.15, MediaQuery.sizeOf(context).width >= 760 ? 12.0 : 8.0);
    _view.value = Matrix4.diagonal3Values(zoom, zoom, zoom)..setTranslationRaw(
      focal.dx - _pinchAnchor!.dx * zoom, focal.dy - _pinchAnchor!.dy * zoom, 0);
  }
  void _endPinch() { _pinchBase = null; _pinchAnchor = null; _saveLayout(flush: true); }
  void _toggleSelection(bool value) => setState(() {
    _selectionPinned = value; if (!value) _ctrlPressed = false; _selected.clear(); _rangeAnchor = null; _selectionStart = null; _selectionEnd = null;
    _selectionPointers.clear(); _selectionZoomBase = null; _selectionZoomDistance = null; _selectionZoomAnchor = null; _selectionPinched = false;
  });
  Rect _boxHeaderBounds(Rect bounds) {
    final width = bounds.width - 64;
    return Rect.fromLTWH(bounds.center.dx - width / 2, bounds.top + 8, width, 32);
  }

  void _toggleThoughtSelection(String id) {
    if (!_selected.add(id)) _selected.remove(id);
    _rangeAnchor = id;
    _rangeAnchorPoint = null;
  }

  String? _resizingThought;
  final _resizeNeighbors = <String>{};
  String? _upperResizeNeighbor;
  bool get _selectionHasPhoto => _selected.any(workspacePhotos.containsKey);

  void _rememberStacks() {
    // Isolate photos even in layouts saved when photos could belong to a stack.
    for (final id in workspacePhotos.keys.where(_positions.containsKey)) {
      _layout.stackGroups[id] = 'photo:$id';
    }
    for(final id in _positions.keys){
      if(_layout.stackGroups.containsKey(id))continue;
      final group=alignedStackMembers(id,_positions,groups:_layout.stackGroups);
      final pending=group.toList();
      for(var index=0;index<pending.length;index++){
        final rect=_bounds(pending[index]);
        for(final candidate in _positions.keys){
          if(group.contains(candidate)||_layout.stackGroups.containsKey(candidate))continue;
          final other=_bounds(candidate);
          if(((rect.top-other.top).abs()-32).abs()<.5 &&
            ((rect.left-other.left).abs()<.5||(rect.right-other.right).abs()<.5)){
            group.add(candidate);pending.add(candidate);
          }
        }
      }
      final key='stack:${DateTime.now().microsecondsSinceEpoch}:$id';
      for(final member in group){_layout.stackGroups[member]=key;}
    }
  }
  Map<String,String>? _stacksBeforeDrop;
  void _joinStack(Iterable<String> moving, String? target){
    _rememberStacks();
    _stacksBeforeDrop=Map.of(_layout.stackGroups);
    final detached=<String,String>{};
    for(final id in moving.where((id) => _positions.containsKey(id) && !workspacePhotos.containsKey(id))){
      final old=_layout.stackGroups[id]!;
      _layout.stackGroups[id]=target!=null?_layout.stackGroups[target]!:
        detached.putIfAbsent(old,()=> 'stack:${DateTime.now().microsecondsSinceEpoch}:$id');
    }
  }
  void _beginResize(String id) {
    _rememberStacks();
    _resizingThought = id; _resizeNeighbors.clear(); _upperResizeNeighbor=null;
    final group=alignedStackMembers(id,_positions,groups:_layout.stackGroups).toList()
      ..sort((a,b)=>_positions[a]!.dy.compareTo(_positions[b]!.dy));
    final index=group.indexOf(id);
    if(index>0){_upperResizeNeighbor=group[index-1];_resizeNeighbors.add(group[index-1]);}
    if(index+1<group.length)_resizeNeighbors.add(group[index+1]);
  }

  void _resizeThought(String id, Size size, Offset shift, {bool snap=true}) => _updateCanvas(() {
    if (_resizingThought != id) _beginResize(id);
    final group = _selected.contains(id)
        ? _selected.where(_positions.containsKey).toSet() : <String>{id};
    final current = _size(id);
    final tolerance=(16/_view.value.storage[0].abs()).clamp(8.0,32.0);
    final upper=_upperResizeNeighbor;
    final upperWidth=upper!=null&&_positions.containsKey(upper)?_size(upper).width:null;
    final snapsToUpper=snap&&size.width!=current.width&&upperWidth!=null&&(size.width-upperWidth).abs()<=tolerance;
    final width = snapsToUpper ? upperWidth : !snap || size.width == current.width ? size.width : snapStackWidth(size.width,
      _resizeNeighbors.where((other)=>!group.contains(other)&&_positions.containsKey(other)).map((other)=>_size(other).width),
      tolerance:tolerance);

    var dx=width-current.width,dy=size.height-current.height;
    var minX=double.negativeInfinity,maxX=double.infinity,minY=double.negativeInfinity,maxY=double.infinity;
    for(final member in group){
      final old=_size(member),point=_positions[member]!;
      minX=math.max(minX,170-old.width);maxX=math.min(maxX,640-old.width);
      minY=math.max(minY,76-old.height);maxY=math.min(maxY,520-old.height);
      if(shift.dx!=0)maxX=math.min(maxX,point.dx-32);
      if(shift.dy!=0)maxY=math.min(maxY,point.dy-32);
    }
    dx=dx.clamp(minX,maxX);dy=dy.clamp(minY,maxY);
    final oldPositions={for(final member in group)member:_positions[member]!};
    for(final member in group){
      final old=_size(member);
      // If the reference is also selected, retain its width for this snap;
      // otherwise resizing it by the same delta would move the target away.
      final memberDx=snapsToUpper&&member==upper?0.0:dx;
      _layout.sizes[member]=Offset(old.width+memberDx,old.height+dy);
      _positions[member]=oldPositions[member]!+Offset(shift.dx!=0?-memberDx:0,shift.dy!=0?-dy:0);
    }
    _displaceNeighbors(group);
    _saveLayout();
  });
  void _displaceNeighbors(Set<String> edited) {
    final boxes = _allRegionBoxes.toList();
    final owners = boxes.where((box) => box.elementIds.any(edited.contains)).toList();
    final fixed = boxes.where((box) =>
        owners.any((owner) => memoBoxContains(box, owner))).toSet();
    final occupied = <MemoBox, Rect>{
      for (final box in fixed)
        if (_boxBounds(box) case final bounds?) box: bounds,
    };
    for (final box in boxes.where((box) => !fixed.contains(box))) {
      final bounds = _boxBounds(box);
      if (bounds == null) continue;
      final shift = releaseBox(bounds, [
        for (final entry in occupied.entries)
          if (!memoBoxContains(box, entry.key) && !memoBoxContains(entry.key, box))
            entry.value,
      ]);
      if (shift != Offset.zero) _moveBox(box, shift);
      occupied[box] = bounds.shift(shift);
    }
  }
  Size _fitThought(ElementRecord record, bool horizontal, bool vertical) {
    final current=_size(record.id);
    final icons=[(memoCommentCounts.value[record.id]??0)>0,record.location!=null,
      record.recordings.isNotEmpty,record.photos.isNotEmpty].where((v)=>v).length;
    final iconWidth=icons==0?0.0:17.0;
    final painter=TextPainter(text:TextSpan(text:record.text,style:Theme.of(context).textTheme.bodyMedium),
      textDirection:Directionality.of(context),textScaler:MediaQuery.textScalerOf(context));
    painter.layout();
    final width=horizontal?(painter.width+16+iconWidth+2).ceilToDouble().clamp(170.0,640.0):current.width;
    painter.layout(maxWidth:width-16-iconWidth);
    var footer=0.0;
    if(record.tags.isNotEmpty){
      final tags=TextPainter(text:TextSpan(text:record.tags.map((tag)=>'#$tag').join('  '),
        style:Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize:10)),
        textDirection:Directionality.of(context),textScaler:MediaQuery.textScalerOf(context),maxLines:1)..layout(maxWidth:width-20);
      footer=tags.height+8;tags.dispose();
    }
    if(_layout.stacked&&record.tags.isEmpty)footer+=24;
    final height=vertical?(math.max(painter.height,icons*13.0)+16+footer+2).ceilToDouble().clamp(76.0,520.0):current.height;
    painter.dispose();return Size(width,height);
  }
  void _moveBox(MemoBox box, Offset shift) {
    final movedBoxes = memoBoxes.where((child) => memoBoxContains(box, child));
    for (final moved in movedBoxes) {
      for (final id in moved.elementIds.where(_positions.containsKey)) {
        _positions[id] = _positions[id]! + shift;
      }
      if (_emptyBoxBounds[moved] case final bounds?) {
        _emptyBoxBounds[moved] = bounds.shift(shift);
      }
      _shiftContainerBounds('box:${moved.name}', shift);
    }
  }
  void _shiftContainerBounds(String key, Offset shift) {
    final bounds = _layout.containerBounds[key];
    if (bounds != null) _layout.containerBounds[key] = bounds.shift(shift);
  }

  MemoBox? _liftedBox;
  Offset? _boxLiftPointer;
  String? _draggedFolder;
  final _frozenFolders = <String, Rect>{};
  Map<String, Rect> _folderGeometry() => {
    ...memoFolderRegions({for (final box in _allRegionBoxes) if (_boxBounds(box) != null) box: _boxBounds(box)!}, _layout.folderPositions, manualBounds: _layout.containerBounds),
    ..._frozenFolders,
  };
  void _moveSelectedTags(Offset shift) {
    for (final id in _selected.where(_tagPositions.containsKey)) {
      _tagPositions[id] = _tagPositions[id]! + shift;
    }
  }
  void _moveFolder(String name, Offset shift) {
    for (final box in memoBoxes.where((box) => box.folder != null && memoFolderContains(name, box.folder!))) { _moveBox(box, shift); }
    for (final folder in memoBoxFolders.where((folder) => memoFolderContains(name, folder))) {
      if (_layout.folderPositions.containsKey(folder)) _layout.folderPositions[folder] = _layout.folderPositions[folder]! + shift;
      _shiftContainerBounds('folder:$folder', shift);
    }
  }
  void _releaseFolder(String name) {
    final folders = _folderGeometry();
    final bounds = folders[name];
    if (bounds == null) return;
    final obstacles = <Rect>[
      for (final other in folders.entries)
        if (!memoFolderContains(name, other.key) && !memoFolderContains(other.key, name)) other.value,
      for (final box in _allRegionBoxes)
        if (box.folder == null || !memoFolderContains(name, box.folder!)) ?_boxBounds(box),
    ];
    _moveFolder(name, releaseBox(bounds, obstacles));
  }
  String? _liftedFolder;
  Offset? _folderLiftPointer;
  Offset _folderLiftShift = Offset.zero;
  void _liftFolder(String name, Offset pointer) {
    setState(() {
      _liftedFolder = name; _folderLiftPointer = pointer; _folderLiftShift = Offset.zero;
      _frozenFolders.clear();
      _frozenFolders.addEntries(_folderGeometry().entries.where((e) => e.key != name && memoFolderContains(e.key, name)));
    });
  }
  void _moveLiftedFolder(String name, Offset pointer) {
    if (_liftedFolder != name || _folderLiftPointer == null) return;
    final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    final bounds = _folderGeometry()[name];
    if (scene == null || bounds == null) return;
    final delta = scene.globalToLocal(pointer) - scene.globalToLocal(_folderLiftPointer!);
    _folderLiftPointer = pointer;
    final shift = Offset(math.max(delta.dx, 32 - bounds.left), math.max(delta.dy, 32 - bounds.top));
    _updateCanvas(() { _moveFolder(name, shift); _moveSelectedTags(shift); _folderLiftShift += shift; });
    _saveLayout();
  }
  void _finishFolderLift(String name, Offset pointer) {
    if (_liftedFolder != name) return;
    final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    if (scene == null) return;
    final point = scene.globalToLocal(pointer);
    final folders = _folderGeometry();
    final blocked = _allRegionBoxes.any((box) =>
      (box.folder == null || !memoFolderContains(name, box.folder!)) && (_boxBounds(box)?.contains(point) ?? false));
    var changed = false;
    setState(() {
      if (blocked) {
        _moveFolder(name, -_folderLiftShift); _moveSelectedTags(-_folderLiftShift);
      } else {
        final targets = folders.entries.where((e) => canMoveMemoFolder(name, e.key) && e.value.contains(point)).toList()
          ..sort((a, b) => memoFolderDepth(b.key).compareTo(memoFolderDepth(a.key)));
        final parent = targets.firstOrNull?.key;
        final oldParent = memoFolderParent(name);
        if (oldParent != parent) {
          if (oldParent != null && _frozenFolders.containsKey(oldParent)) {
            _layout.folderPositions[oldParent] = _frozenFolders[oldParent]!.topLeft + const Offset(28, 44);
          }
          moveMemoFolder(name, parent); changed = true;
        }
      }
      _liftedFolder = null; _folderLiftPointer = null; _frozenFolders.clear();
      final beforeRelease = _folderGeometry()[name]?.topLeft;
      for (String? folder = name; folder != null; folder = memoFolderParent(folder)) { _releaseFolder(folder); }
      if (beforeRelease != null) _moveSelectedTags(_folderGeometry()[name]!.topLeft - beforeRelease);
    });
    if (changed) widget.onChanged();
    if (blocked) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('폴더는 메모상자에 넣을 수 없습니다. 폴더 안이나 빈 곳에 놓아주세요.')));
    _saveLayout(flush: true);
  }
  void _liftBox(MemoBox box, Offset pointer) {
    setState(() {
      _liftedBox = box; _boxLiftPointer = pointer; _frozenFolders.clear();
      _liftBoxes
        ..clear()
        ..addEntries(_allRegionBoxes
            .where((parent) => parent != box && memoBoxContains(parent, box))
            .expand((parent) => [if (_boxBounds(parent) case final bounds?) MapEntry(parent, bounds)]));
      if (box.folder != null) {
        _frozenFolders.addEntries(_folderGeometry().entries.where((e) => memoFolderContains(e.key, box.folder!)));
      }
    });
  }
  void _moveLiftedBox(MemoBox box, Offset pointer) {
    if (!identical(_liftedBox, box) || _boxLiftPointer == null) return;
    final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    if (scene == null) return;
    final delta = scene.globalToLocal(pointer) - scene.globalToLocal(_boxLiftPointer!);
    _boxLiftPointer = pointer;
    _updateCanvas(() => _dragBox(box, delta));
  }
  void _finishBoxDrag(MemoBox box, [Offset? pointer]) {
    if (identical(_liftedBox, box) && pointer != null) _boxLiftPointer = pointer;
    var changed = false;
    setState(() {
      final oldFolder = box.folder;
      final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
      final lifted = identical(_liftedBox, box);
      if (pointer != null && scene != null) {
        final point = scene.globalToLocal(pointer);
        final targetBox = _boxAt(point, where: (target) => canMoveMemoBox(box, target));
        final legacyTargets = _folderGeometry().entries
            .where((entry) => entry.value.contains(point)).toList()
          ..sort((a, b) => memoFolderDepth(b.key).compareTo(memoFolderDepth(a.key)));
        final target = targetBox?.name ?? (lifted ? legacyTargets.firstOrNull?.key : oldFolder);
        if (oldFolder != target) {
          if (oldFolder != null && _frozenFolders.containsKey(oldFolder)) {
            _layout.folderPositions[oldFolder] = _frozenFolders[oldFolder]!.topLeft + const Offset(28, 44);
          }
          if (_emptyBoxBounds[box] case final bounds?) {
            _layout.containerBounds.putIfAbsent('box:${box.name}', () => bounds);
          }
          box.folder = target;
          changed = true;
        }
      }
      _liftedBox = null;
      _boxLiftPointer = null;
      _frozenFolders.clear();
      _liftBoxes.clear();
      final beforeRelease = _boxBounds(box)?.topLeft;
      if (!changed) _releaseBox(box);
      for (String? parent = box.folder; parent != null; parent = memoFolderParent(parent)) { _releaseFolder(parent); }
      if (beforeRelease != null) _moveSelectedTags(_boxBounds(box)!.topLeft - beforeRelease);
    });
    // Publish the drop geometry before the membership save captures the snapshot.
    _saveLayout(flush: true);
    if (changed) widget.onChanged();
  }
  void _releaseBox(MemoBox box) {
    final bounds = _boxBounds(box);
    if (bounds == null) return;
    _moveBox(box, releaseBox(bounds, [
      for (final other in _allRegionBoxes) if (!memoBoxContains(box, other) && !memoBoxContains(other, box)) ?_boxBounds(other),
      for (final folder in _folderGeometry().entries)
        if (box.folder == null || !memoFolderContains(folder.key, box.folder!)) folder.value,
    ]));
  }
  void _dragBox(MemoBox box, Offset delta) {
    final bounds = _boxBounds(box);
    if (bounds == null) return;
    final shift = Offset(math.max(delta.dx, 32 - bounds.left), math.max(delta.dy, 32 - bounds.top));
    _moveBox(box, shift); _moveSelectedTags(shift);
    _saveLayout();
  }

  bool _routeVisible = true, _appActive = true;
  ModalRoute<dynamic>? _route;
  Size _size(String id) {
    final size = _layout.sizes[id];
    final photo = workspacePhotos[id];
    if (photo != null) {
      final ratio = photo.aspectRatio;
      final width = math.min(size?.dx ?? 230.0, 640.0 * ratio);
      return Size(width, width / ratio);
    }
    return size == null
        ? const Size(230, 120)
        : Size(size.dx, size.dy);
  }

  void _resizeCanvasPhoto(String id, Size size, Offset shift) {
    final previous = _positions[id]!;
    if ((previous + shift).dx < 32 || (previous + shift).dy < 32) return;
    _updateCanvas(() {
      _positions[id] = previous + shift;
      _layout.sizes[id] = Offset(size.width, size.height);
      _displaceNeighbors({id});
    });
    _saveLayout();
  }

  Rect _bounds(String id) => _positions[id]! & _size(id);
  @override
  void initState() {
    super.initState();
    _ctrlPressed = HardwareKeyboard.instance.isControlPressed;
    HardwareKeyboard.instance.addHandler(_controlSelection);
    widget.storage?.liveChanges.addListener(_remoteLayoutChanged);
    _filters.addListener(_filterChanged);
    final base = widget.box?.layout ?? pageGraphLayout;
    final target=base.blockLayout;
    _layout = widget.storage==null?target:GraphLayout.fromJson(target.toJson());
    _publishedLayout=GraphLayout.fromJson(_layout.toJson());
    _positions.addAll(_layout.positions);
    _tagPositions.addAll(_layout.tags);
    _query = _layout.query;
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
    _rememberStacks();
  }
  _CanvasState _captureCanvas() {
    final state = _CanvasState();
    state.layout
      ..stacked = _layout.stacked
      ..layers.addAll(_layout.layers)
      ..positions.addAll(_positions)
      ..sizes.addAll(_layout.sizes)
      ..tags.addAll(_tagPositions)
      ..folderPositions.addAll(_layout.folderPositions)
      ..containerBounds.addAll(_layout.containerBounds)
      ..stackGroups.addAll(_layout.stackGroups);
    state.emptyBoxes.addAll(_emptyBoxBounds);
    for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
      for (final id in box.elementIds) {
        state.thoughtBoxes[id] = box;
      }
      if (box.folder case final folder?) state.boxFolders[box] = folder;
    }
    state.folderParents.addAll(memoBoxFolderParents);
    return state;
  }

  void _rememberEdit(_CanvasState? before) {
    if (before == null) return;
    final after = _captureCanvas();
    if (!before.keepChangesAgainst(after)) return;
    setState(() {
      _undo.add((before: before, after: after));
      if (_undo.length > _historyLimit) _undo.removeAt(0);
      _redo.clear();
    });
  }

  void _editCanvasLayout(VoidCallback edit) {
    final before = _captureCanvas();
    setState(edit);
    _rememberEdit(before);
    _saveLayout(flush: true);
  }

  void _stepHistory({required bool redo}) {
    final source = redo ? _redo : _undo;
    final destination = redo ? _undo : _redo;
    if (!_canEdit || source.isEmpty || _activeCanvasPointers.isNotEmpty) return;
    final entry = source.removeLast();
    final expected = redo ? entry.before : entry.after;
    final desired = redo ? entry.after : entry.before;
    final current = _captureCanvas();
    var containersChanged = false;
    setState(() {
      _layout.positions..clear()..addAll(_positions);
      _layout.tags..clear()..addAll(_tagPositions);
      // Apply inverse changes only where the current value still matches the edit.
      _layout.mergeRemote(desired.layout, expected.layout);
      _positions..clear()..addAll(_layout.positions);
      _tagPositions..clear()..addAll(_layout.tags);
      for (final box in {...expected.emptyBoxes.keys, ...desired.emptyBoxes.keys}) {
        if (!memoBoxes.contains(box) || _emptyBoxBounds[box] != expected.emptyBoxes[box]) continue;
        final bounds = desired.emptyBoxes[box];
        if (bounds == null) {
          _emptyBoxBounds.remove(box);
        } else {
          _emptyBoxBounds[box] = bounds;
        }
      }
      for (final id in {...expected.thoughtBoxes.keys, ...desired.thoughtBoxes.keys}) {
        if ((elements.byId(id) == null && !workspacePhotos.containsKey(id)) || current.thoughtBoxes[id] != expected.thoughtBoxes[id]) continue;
        final box = desired.thoughtBoxes[id];
        if (box != null && !memoBoxes.contains(box)) continue;
        moveThoughtToBox(id, box ?? ensureUnclassifiedBox());
        containersChanged = true;
      }
      for (final box in {...expected.boxFolders.keys, ...desired.boxFolders.keys}) {
        if (!memoBoxes.contains(box) || box.folder != expected.boxFolders[box]) continue;
        final folder = desired.boxFolders[box];
        if (folder != null && !memoBoxFolders.contains(folder)) continue;
        box.folder = folder;
        containersChanged = true;
      }
      for (final folder in {...expected.folderParents.keys, ...desired.folderParents.keys}) {
        final parent = desired.folderParents[folder];
        if (memoFolderParent(folder) != expected.folderParents[folder] ||
            !canMoveMemoFolder(folder, parent)) continue;
        moveMemoFolder(folder, parent);
        containersChanged = true;
      }
      _selected.clear();
      _rangeAnchor = null;
      _sync();
      destination.add(entry);
    });
    _saveTimer?.cancel();
    _saveTimer = null;
    _flushLayout(mergeRemote: false);
    if (containersChanged) widget.onChanged();
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
  void _flushLayout({bool mergeRemote = true}) {
    // Keep the pre-drag merge baseline until all pointers are released. Publishing
    // midway makes a delayed server snapshot look newer than the user's drop.
    if(!_canEdit || _activeCanvasPointers.isNotEmpty)return;
    _layout.positions..clear()..addAll(_positions);
    _layout.tags..clear()..addAll(_tagPositions);
    _layout.viewport = _view.value.storage.toList();
    _layout.query = _query;
    _layout.hideTags = _hideTags;
    if(widget.storage!=null){
      if (mergeRemote && _remoteLayoutPending) {
        _layout.mergeRemote(_targetLayout, _publishedLayout);
        _publishedLayout = GraphLayout.fromJson(_targetLayout.toJson());
      }
      _remoteLayoutPending = false;
      _positions..clear()..addAll(_layout.positions);
      _tagPositions..clear()..addAll(_layout.tags);
      _targetLayout.copyFrom(_layout,includeBlocks:false);
      // Local publication is not a server acknowledgement. Keep the remote
      // baseline until a live snapshot confirms this move.
    }
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
  @override void onTabPaused() {
    _ctrlPressed = false; _shiftPressed = false;
    _saveLayout(flush: true);
  }
  @override void onTabResumed() {
    _remoteLayoutChanged();
  }
  @override
  void didPushNext() {
    _routeVisible = false;
    _saveLayout(flush: true);
  }
  @override
  void didPopNext() {
    _routeVisible = true;
    if (mounted && tabActive) setState(_sync);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _ctrlPressed = false; _shiftPressed = false;
      _saveLayout(flush: true);
    } else if (mounted && tabActive && _routeVisible) {
      setState(_sync);
    }
  }
  final _photoCanvasRecords = <String, ElementRecord>{};
  List<ElementRecord> get _scopeRecords => [
    ...elements.records.values,
    for (final photo in workspacePhotos.values)
        _photoCanvasRecords.putIfAbsent(photo.id, () =>
          ElementRecord.restored(photo.id, photo.displayTitle, photo.createdAt))
          ..text = photo.displayTitle
          ..indexLabel = photo.label,
  ];
  List<ElementRecord> get _records => _scopeRecords.where((r) => canBrowseThought(r) &&
    _filters.matches(r) &&
    (_query.isEmpty || r.indexLabel.toLowerCase().contains(_query) || r.text.toLowerCase().contains(_query) || r.tags.any((tag) => tag.toLowerCase().contains(_query)))).toList();
  void _sync() {
    _photoCanvasRecords.removeWhere((id, _) => !workspacePhotos.containsKey(id));
    final scope = _scopeRecords;
    final hadPositions = _positions.isNotEmpty;
    final newIds = scope.where((r) => !_positions.containsKey(r.id)).map((r) => r.id).toSet();
    final scopeIds = scope.map((r) => r.id).toSet();
    _layout.layers.removeWhere((id) => !scopeIds.contains(id));
    _layout.layers.addAll(scopeIds.where((id) => !_layout.layers.contains(id)).toList());
    _selected.removeWhere((id) => !scopeIds.contains(id) && !_tagPositions.containsKey(id));
    closeVacatedStackSlots(_positions, Map.of(_positions), _positions.keys.where((id) => !scopeIds.contains(id)).toSet(),groups:_layout.stackGroups);
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
    _arrangeBlocks(ordered);
    arrangeCanvasTags(tags: tags, cardBounds: _positions.keys.map(_bounds), tagPositions: _tagPositions);
    if (newIds.isNotEmpty) _separateOverlappingBoxes();
    {
      final loose = newIds.where((id) => !memoBoxes.any((box) => !box.isUnclassified && box.elementIds.contains(id))).toList();
      final occupied = [
        for (final id in _positions.keys.where((id) => !loose.contains(id))) _bounds(id),
        for (final box in _allRegionBoxes) ?_boxBounds(box),
        for (final point in _tagPositions.values) tagBounds(point),
      ];
      final y = occupied.map((r) => r.bottom).fold(400.0, math.max) + 120;
      for (var i = 0; i < loose.length; i++) {
        _positions[loose[i]] = Offset(640 + (i % 5) * 290, y + (i ~/ 5) * 180);
      }
    }
    if (!hadPositions && _positions.isNotEmpty) _centered = false;
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
  Rect? _regionBounds(MemoBox box, Map<String, Offset> positions, {Set<MemoBox> ancestors = const {}, bool includeManual = true, bool hitTest = false}) {
    if (ancestors.contains(box)) return null;
    final path = {...ancestors, box};
    final enclosed = [
      for (final id in box.elementIds.where(positions.containsKey))
        positions[id]! & _size(id),
      for (final child in childMemoBoxes(box))
        ?(_frozenBoxBounds(child, hitTest: hitTest) ?? _regionBounds(child, positions, ancestors: path, hitTest: hitTest) ?? _layout.containerBounds['box:${child.name}'] ?? _emptyBoxBounds[child]),
    ];
    if (enclosed.isEmpty) return null;
    final bounds = enclosed.reduce((a, b) => a.expandToInclude(b));
    final natural = Rect.fromLTRB(bounds.left - 32, bounds.top - 52, bounds.right + 32, bounds.bottom + 32);
    final manual = includeManual ? _layout.containerBounds['box:${box.name}'] : null;
    return manual?.expandToInclude(natural) ?? natural;
  }
  bool _inside(Rect bounds, Offset point) => bounds.contains(point);
  Iterable<MemoBox> get _regionBoxes => memoBoxes.where((box) =>
      !box.isUnclassified && (_filters.isEmpty || _filters.includesBox(box) ||
      (_filters.tags.isNotEmpty && _records.any((r) => box.elementIds.contains(r.id)))));
  Iterable<MemoBox> get _allRegionBoxes => memoBoxes.where((box) => !box.isUnclassified);
  Rect? _frozenBoxBounds(MemoBox box, {required bool hitTest}) =>
      hitTest || _liftedThought != null || _selectionLifted || _liftedBox != null
          ? _liftBoxes[box] : null;
  Rect? _boxBounds(MemoBox box, {bool hitTest = false}) =>
      _frozenBoxBounds(box, hitTest: hitTest) ??
      _regionBounds(box, _positions, hitTest: hitTest) ??
      _layout.containerBounds['box:${box.name}'] ?? _emptyBoxBounds[box];

  MemoBox? _boxAt(Offset point, {required bool Function(MemoBox) where}) {
    final targets = [
      for (final box in _regionBoxes.where(where))
        if (_boxBounds(box, hitTest: true) case final bounds? when bounds.contains(point))
          (box: box, area: bounds.width * bounds.height),
    ]..sort((a, b) => a.area.compareTo(b.area));
    return targets.firstOrNull?.box;
  }

  Offset _limitThoughtDrag(Set<String> moving, Offset delta) {
    if (delta == Offset.zero || _selectionLifted || _liftedThought != null) return delta;
    final owners = _allRegionBoxes.where((box) => box.elementIds.any(moving.contains)).toList();
    if (owners.isEmpty) return delta;
    var shift = delta;
    for (final box in _allRegionBoxes.where((box) => owners.any((owner) => memoBoxContains(box, owner)))) {
      final start = _boxBounds(box);
      if (start == null) continue;
      final proposed = {..._positions, for (final id in moving.where(_positions.containsKey)) id: _positions[id]! + shift};
      final requested = _regionBounds(box, proposed);
      if (requested == null) continue;
      final enclosedIds = {for (final child in _allRegionBoxes.where((other) => memoBoxContains(box, other))) ...child.elementIds};
      final obstacles = <Rect>[
        for (final other in _allRegionBoxes)
          if (!memoBoxContains(box, other) && !memoBoxContains(other, box)) ?_boxBounds(other),
        for (final id in _positions.keys)
          if (!moving.contains(id) && !enclosedIds.contains(id)) _bounds(id),
        if (!_hideTags)
          for (final tag in _records.expand((record) => record.tags).toSet())
            if (_tagPositions.containsKey('tag:$tag') && !moving.contains('tag:$tag')) _tagBounds('tag:$tag'),
        if (memoBoxFolders.isNotEmpty)
          for (final folder in _folderGeometry().entries)
            if (box.folder == null || !memoFolderContains(folder.key, box.folder!)) folder.value,
      ];
      final limited = _limitContainerResize(start, start.expandToInclude(requested), obstacles);
      shift = Offset(
        shift.dx > 0 ? math.max(0, shift.dx - math.max(0, requested.right - limited.right))
            : math.min(0, shift.dx + math.max(0, limited.left - requested.left)),
        shift.dy > 0 ? math.max(0, shift.dy - math.max(0, requested.bottom - limited.bottom))
            : math.min(0, shift.dy + math.max(0, limited.top - requested.top)),
      );
    }
    return shift;
  }

  bool _dropIntoBox(Offset point, Iterable<String> ids) {
    final moving = ids.where(_positions.containsKey).toList();
    if (moving.isEmpty) return false;
    final box = _boxAt(point, where: (_) => true);
    if (box == null || moving.every(box.elementIds.contains)) return false;
    if (!_selectionLifted && _liftedThought == null &&
        _allRegionBoxes.any((owner) => !memoBoxContains(owner, box) && owner.elementIds.any(moving.contains))) return false;
    _joinStack(moving, null);
    for (final id in moving) {
      final old = memoBoxes.where((box) => !box.isUnclassified && box.elementIds.contains(id)).firstOrNull;
      if (old != null) {
        final bounds = _boxBounds(old);
        if (bounds != null) _emptyBoxBounds[old] = bounds;
      }
      moveThoughtToBox(id, box);
    }
    _liftBoxes.clear();
    _changed();
    return true;
  }

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
  void _separateOverlappingBoxes() {
    for (final box in _allRegionBoxes) {
      final bounds = _boxBounds(box);
      if (bounds == null) continue;
      _moveBox(box, releaseBox(bounds, [
        for (final other in _allRegionBoxes) if (!memoBoxContains(box, other) && !memoBoxContains(other, box)) ?_boxBounds(other),
      ]));
    }
    // Recompute nested folder outlines after their children have grown/moved.
    final folders = memoBoxFolders.toList()
      ..sort((a, b) => memoFolderDepth(b).compareTo(memoFolderDepth(a)));
    for (final folder in folders) { _releaseFolder(folder); }
    // Ungrouped boxes must also stay outside the expanded folder outlines.
    for (final box in _allRegionBoxes.where((box) => box.folder == null)) { _releaseBox(box); }
  }

  void _compactBoxSpace() {
    final boxes = _allRegionBoxes.toList()
      ..sort((a, b) => memoBoxPath(b).length.compareTo(memoBoxPath(a).length));
    _editCanvasLayout(() {
      for (final box in boxes) {
        final key = 'box:${box.name}';
        final manual = _layout.containerBounds[key];
        if (manual == null) continue;
        final natural = _regionBounds(box, _positions, includeManual: false);
        if (natural != null && manual.expandToInclude(natural) != natural) {
          _layout.containerBounds.remove(key);
          _emptyBoxBounds.remove(box);
        }
      }
    });
  }

  Future<void> _confirmResetArrangement(bool stacked) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('초기화 할까요?'),
        content: const Text('지금까지 정리한 내용이 초기화됩니다.\n되돌릴까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('초기화')),
        ],
      ),
    );
    if (mounted && confirmed == true && _canEdit) _resetArrangement(stacked);
  }

  void _resetArrangement(bool stacked) {
    _editCanvasLayout(() {
      _positions.clear(); _tagPositions.clear(); _emptyBoxBounds.clear(); _liftBoxes.clear();
      _layout.sizes.clear(); _layout.folderPositions.clear(); _layout.containerBounds.clear(); _layout.viewport = null;
      _layout.stackGroups.clear(); _layout.stacked = stacked; _selected.clear(); _layout.layers.clear();
      _draggingId = null; _hoverBox = null;
      _query = ''; _search.clear();
      _centered = false; _sync();
      _arrangeThoughts(stacked);
    });
  }
  void _arrangeThoughts(bool stacked) {
    final boxes = memoBoxes.where((box) => !box.isUnclassified).toList();
    final scope = _scopeRecords;
    final order = {for (var i = 0; i < scope.length; i++) scope[i].id: i};
    _layout.layers.clear();
    final loose = _scopeRecords.map((r) => r.id).where((id) => !boxes.any((box) => box.elementIds.contains(id))).toList();
    void arrangeMembers(List<String> ids) {
      if (ids.isEmpty) return;
      ids.sort((a, b) => order[a]!.compareTo(order[b]!));
      _layout.layers.addAll(ids);
      final width = ids.map((id) => _size(id).width).reduce(math.max);
      final height = ids.map((id) => _size(id).height).reduce(math.max);
      final cards = stacked ? ids.where((id) => !workspacePhotos.containsKey(id)).toList() : ids;
      final columns = stacked ? (cards.length / 8).ceil() : math.sqrt(cards.length).ceil();
      for (var i = 0; i < cards.length; i++) {
        _positions[cards[i]] = Offset(640 + (stacked ? i ~/ 8 : i % columns) * (width + 24),
          400 + (stacked ? i % 8 : i ~/ columns) * (stacked ? 32 : height + 24));
      }
      if (stacked) {
        var x = 640 + columns * (width + 24);
        for (final id in ids.where(workspacePhotos.containsKey)) {
          _positions[id] = Offset(x, 400);
          x += _size(id).width + 24;
        }
      }
    }
    for (final box in boxes) {
      final ids = box.elementIds.where(_positions.containsKey).toList();
      arrangeMembers(ids);
      if (ids.isEmpty) _emptyBoxBounds[box] = const Rect.fromLTWH(640, 400, 260, 260);
    }
    arrangeMembers(loose);
    Rect pack(String? folder, {MemoBox? parent}) {
      final units = <({Rect bounds, List<String> ids, List<MemoBox> boxes, List<String> folders})>[];
      final children = childMemoBoxes(parent).where((box) => parent != null ||
          (memoBoxFolders.contains(box.folder) ? box.folder : null) == folder);
      for (final box in children) {
        if (childMemoBoxes(box).isNotEmpty) pack(null, parent: box);
        final subtree = boxes.where((member) => memoBoxContains(box, member)).toList();
        units.add((bounds: _boxBounds(box)!,
          ids: subtree.expand((member) => member.elementIds).where(_positions.containsKey).toList(),
          boxes: subtree, folders: []));
      }
      if (parent == null) {
        for (final child in memoBoxFolders.where((name) => memoFolderParent(name) == folder)) {
          final bounds = pack(child);
          final roots = boxes.where((box) => box.folder != null && memoFolderContains(child, box.folder!));
          final childBoxes = boxes.where((box) => roots.any((root) => memoBoxContains(root, box))).toList();
          units.add((bounds: bounds, ids: childBoxes.expand((box) => box.elementIds).where(_positions.containsKey).toList(),
            boxes: childBoxes, folders: memoBoxFolders.where((name) => memoFolderContains(child, name)).toList()));
        }
      }
      final directIds = parent != null ? parent.elementIds.where(_positions.containsKey).toList()
          : folder == null ? loose : <String>[];
      if (directIds.isNotEmpty) {
        units.add((bounds: directIds.map(_bounds).reduce((a, b) => a.expandToInclude(b)), ids: directIds, boxes: [], folders: []));
      }
      if (units.isEmpty) {
        if (folder != null) _layout.folderPositions[folder] = const Offset(640, 400);
        return const Rect.fromLTWH(612, 356, 356, 272);
      }
      final area = units.fold(0.0, (sum, unit) => sum + (unit.bounds.width + 80) * (unit.bounds.height + 80));
      final limit = math.max(units.map((unit) => unit.bounds.width).reduce(math.max), math.sqrt(area) * 1.3);
      var x = 640.0, y = 400.0, rowHeight = 0.0;
      Rect? total;
      for (final unit in units) {
        if (x > 640 && x + unit.bounds.width > 640 + limit) { x = 640; y += rowHeight + 80; rowHeight = 0; }
        final shift = Offset(x - unit.bounds.left, y - unit.bounds.top);
        for (final id in unit.ids) { _positions[id] = _positions[id]! + shift; }
        for (final box in unit.boxes) { if (_emptyBoxBounds.containsKey(box)) _emptyBoxBounds[box] = _emptyBoxBounds[box]!.shift(shift); }
        for (final name in unit.folders) { if (_layout.folderPositions.containsKey(name)) _layout.folderPositions[name] = _layout.folderPositions[name]! + shift; }
        final moved = unit.bounds.shift(shift);
        total = total == null ? moved : total.expandToInclude(moved);
        x = moved.right + 80; rowHeight = math.max(rowHeight, moved.height);
      }
      final bounds = total!;
      return folder == null ? bounds : Rect.fromLTRB(bounds.left - 28, bounds.top - 44, bounds.right + 28, bounds.bottom + 28);
    }
    pack(null);
    for (final box in boxes) {
      if (childMemoBoxes(box).isEmpty && !box.elementIds.any(_positions.containsKey)) {
        _layout.containerBounds['box:${box.name}'] = _emptyBoxBounds[box]!;
      }
    }
    {
      final occupied = <Rect>[for (final box in boxes) _boxBounds(box)!, ...loose.map(_bounds)];
      for (final tag in _tagPositions.keys.toList()) {
        final related = _scopeRecords.where((r) => r.tags.contains(tag.substring(4))).map((r) => r.id).toList();
        if (related.isEmpty) continue;
        final candidates = boxes.where((box) => related.any(box.elementIds.contains)).toList()
          ..sort((a, b) => related.where(b.elementIds.contains).length.compareTo(related.where(a.elementIds.contains).length));
        final anchor = candidates.isEmpty ? related.map(_bounds).reduce((a, b) => a.expandToInclude(b)) : _boxBounds(candidates.first)!;
        var rect = Rect.fromLTWH(anchor.right + 24, anchor.top, graphTagSize.width, graphTagSize.height);
        while (occupied.any((other) => other.inflate(8).overlaps(rect))) {
          rect = rect.shift(const Offset(0, 64));
          if (rect.top > anchor.bottom + 256) rect = Rect.fromLTWH(rect.left + graphTagSize.width + 24, anchor.top, rect.width, rect.height);
        }
        _tagPositions[tag] = rect.center; occupied.add(rect);
      }
    }
  }
  bool _deletingContainer=false;
  Future<void> _persistContainerDelete()async{
    _saveLayout(flush:true);_changed();
    final save=widget.onSave??saveWorkspaceContent;
    if(save!=null)await save();
    await widget.storage?.syncFolders?.call();
  }
  void _removeBoxes(Set<String> names) {
    removeMemoBoxesKeepingThoughts(names);
    _filters.boxes.removeWhere((box) => names.contains(box.name));
    _emptyBoxBounds.removeWhere((box, _) => names.contains(box.name));
    for (final name in names) { _layout.containerBounds.remove('box:$name'); }
  }

  void _trashThoughts(Set<String> ids) {
    final words = ids.map((id) => elements.byId(id)?.text).nonNulls.toList();
    for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
      box.elementIds.removeAll(ids);
    }
    _selected.removeAll(ids);
    if (ids.contains(_rangeAnchor)) {
      _rangeAnchor = null;
      _rangeAnchorPoint = null;
    }
    elements.removeAll(words);
  }

  Future<void> _removeCanvasBoxes(Set<String> names, ContainerDeletion choice) async {
    if (!_canEdit || _deletingContainer) return;
    _deletingContainer = true;
    try {
      await widget.storage?.writable();
      if (!mounted || !_canEdit) return;
      final boxes = choice == ContainerDeletion.withThoughts
          ? memoBoxSubtrees(names)
          : memoBoxes.where((box) => !box.isUnclassified && names.contains(box.name));
      final ids = boxes.expand((box) => box.elementIds).toSet();
      _removeBoxes(boxes.map((box) => box.name).toSet());
      if (choice == ContainerDeletion.withThoughts) {
        workspacePhotos.removeWhere((id, _) => ids.contains(id));
        _trashThoughts(ids);
      }
      await _persistContainerDelete();
    } finally {
      _deletingContainer = false;
    }
  }

  Future<void> _deleteCanvasBox(MemoBox box) async {
    if (!_canEdit || box.isUnclassified || _deletingContainer) return;
    final choice = await confirmContainerDeletion(
      context, box.name,
    );
    if (choice == null || !mounted) return;
    try {
      await _removeCanvasBoxes({box.name}, choice);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상자 삭제를 저장하지 못했습니다. $error')),
      );
    }
  }

  void _removeFolder(String folder) {
    removeMemoFolderKeepingContents(folder);
    _layout.folderPositions.remove(folder);
    _layout.containerBounds.remove('folder:$folder');
    _frozenFolders.remove(folder);
  }

  Future<void> _deleteCanvasFolder(String folder) async {
    if (!_canEdit || _deletingContainer) return;
    final choice = await confirmContainerDeletion(
      context, folder, isFolder: true,
    );
    if (choice == null || !mounted || !_canEdit || _deletingContainer) return;
    _deletingContainer = true;
    try {
      await widget.storage?.writable();
      if (!mounted || !_canEdit || !memoBoxFolders.contains(folder)) return;
      if (choice == ContainerDeletion.withThoughts) {
        final boxes = memoBoxes.where((box) =>
          !box.isUnclassified && box.folder != null && memoFolderContains(folder, box.folder!),
        ).toList();
        final ids = boxes.expand((box) => box.elementIds).toSet();
        final subtree = memoBoxFolders.where((name) => memoFolderContains(folder, name)).toList()
          ..sort((a, b) => memoFolderDepth(b).compareTo(memoFolderDepth(a)));
        _removeBoxes(boxes.map((box) => box.name).toSet());
        for (final name in subtree) {
          _removeFolder(name);
        }
        _trashThoughts(ids);
      } else {
        _removeFolder(folder);
      }
      await _persistContainerDelete();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('폴더 삭제를 저장하지 못했습니다. $error')),
      );
    } finally {
      _deletingContainer = false;
    }
  }

  Future<void> _deleteSelectedThoughts(Set<String> ids) async {
    ids = ids.where((id) => !workspacePhotos.containsKey(id)).toSet();
    if (ids.isEmpty || !_canEdit || _deletingContainer) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('선택한 생각을 삭제하시겠습니까?'),
        content: Text('생각 ${ids.length}개가 휴지통으로 이동합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (accepted != true || !mounted || !_canEdit || _deletingContainer) return;
    _deletingContainer = true;
    try {
      await widget.storage?.writable();
      if (!mounted || !_canEdit) return;
      _trashThoughts(ids);
      _saveLayout(flush: true);
      _changed();
      final save = widget.onSave ?? saveWorkspaceContent;
      if (save != null) await save();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('생각을 삭제하지 못했습니다. $error')),
      );
    } finally {
      _deletingContainer = false;
    }
  }
  Future<void> _createBox() async {
    final box = await createMemoBox(context);
    if (mounted && box != null) _changed();
  }

  void _remoteLayoutChanged(){
    if (!mounted) return;
    _remoteLayoutPending = true;
    if (!tabActive || _activeCanvasPointers.isNotEmpty) return;
    _remoteLayoutPending = false;
    _layout.positions..clear()..addAll(_positions);
    _layout.tags..clear()..addAll(_tagPositions);
    _layout.mergeRemote(_targetLayout,_publishedLayout);
    _publishedLayout=GraphLayout.fromJson(_targetLayout.toJson());
    _positions..clear()..addAll(_layout.positions);
    _tagPositions..clear()..addAll(_layout.tags);
    setState(_sync);
  }
  void _pointerFinished(int pointer){
    _activeCanvasPointers.remove(pointer);
    widget.storage?.canvasInteracting=_activeCanvasPointers.isNotEmpty;
    // A pointer release publishes locally; it must not acknowledge that publication
    // as a server snapshot, or the next delayed snapshot can undo the drag.
    if (_activeCanvasPointers.isEmpty) {
      final before = _gestureBefore;
      _gestureBefore = null;
      scheduleMicrotask(() {
        if (!mounted) return;
        _rememberEdit(before);
        _saveLayout(flush: true);
      });
    }
  }
  void _storeChanged() { if (mounted && tabActive && _routeVisible && _appActive) setState(_sync); }
  void _changed() { widget.onChanged(); setState(_sync); }
  Future<void> _create({MemoBox? target, bool useFilter = true}) async {
    final record = await showThoughtCapture(context, widget.storage);
    if (record == null || !mounted) return;
    final box = target ?? (useFilter ? _filterBox : null);
    if (memoBoxes.contains(box)) moveThoughtToBox(record.id, box!);
    _changed();
    fillVoiceBody(record);
    final save = widget.onSave ?? saveWorkspaceContent;
    try {
      await save?.call();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('생각을 동기화하지 못했습니다. $error')),
      );
    }
  }
  @override
  void dispose() {
    _setCanvasBrowserMenu(false);
    HardwareKeyboard.instance.removeHandler(_controlSelection);
    _activeCanvasPointers.clear();
    if(tabActive)_saveLayout(flush: true);
    widget.storage?.liveChanges.removeListener(_remoteLayoutChanged);
    widget.storage?.canvasInteracting=false;
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    workspaceRouteObserver.unsubscribe(this);
    _filters.removeListener(_filterChanged);
    if (widget.filters == null) _filters.dispose();
    elements.removeListener(_storeChanged);
    _view.removeListener(_saveLayout);
    _view.dispose(); _searchFocus.dispose(); _search.dispose(); _canvasUpdates.dispose();
    super.dispose();
  }
  Offset? _rangeAnchorPoint;
  final _tagSizeCache = <(String, TextStyle?, TextScaler, TextDirection), Size>{};
  Rect _tagBounds(String id) {
    final style=Theme.of(context).textTheme.labelLarge;
    final scaler=MediaQuery.textScalerOf(context), direction=Directionality.of(context);
    final key=(id,style,scaler,direction);
    final size=_tagSizeCache.putIfAbsent(key,(){
      final text=TextPainter(text:TextSpan(text:'#${id.substring(4)}',style:style),
        textDirection:direction,textScaler:scaler,maxLines:1)..layout();
      final size=Size((text.width+20).ceilToDouble().clamp(32,graphTagSize.width),math.max(32,(text.height+10).ceilToDouble()));
      text.dispose();return size;
    });
    return Rect.fromCenter(center:_tagPositions[id]!,width:size.width,height:size.height);
  }
  Offset _selectionPoint(String id) => _positions[id] ?? _tagPositions[id]!;
  void _setSelectionPoint(String id, Offset point) {
    if (_positions.containsKey(id)) { _positions[id] = point; }
    else if (_tagPositions.containsKey(id)) { _tagPositions[id] = point; }
  }
  Rect _selectionBounds(String id) => _positions.containsKey(id) ? _bounds(id) : _tagBounds(id);
  String? _hitSelection(Offset point, List<ElementRecord> records) {
    if (!_hideTags) {
      final tags = records.expand((r) => r.tags).toSet();
      for (final tag in tags.toList().reversed) {
        final id = 'tag:$tag';
        if (_tagPositions.containsKey(id) && _tagBounds(id).contains(point)) return id;
      }
    }
    return records.where((r) => _bounds(r.id).contains(point)).lastOrNull?.id;
  }
  void _closeMovedSlots(Map<String, Offset> origins, {bool compactSelection = true}) {
    final before = {..._positions, ...Map.fromEntries(origins.entries.where((e) => _positions.containsKey(e.key)))};
    final moved = origins.keys.where((id) => _positions.containsKey(id) && (_positions[id]!-origins[id]!).distance > .5).toSet();
    final groups = _stacksBeforeDrop ?? _layout.stackGroups;
    if (compactSelection && moved.length > 1) {
      final visited = <String>{};
      for (final id in moved) {
        if (visited.contains(id)) continue;
        final members = alignedStackMembers(id, before, groups: groups).toList()
          ..sort((a, b) => before[a]!.dy.compareTo(before[b]!.dy));
        visited.addAll(members);
        int? previous;
        for (var index = 0; index < members.length; index++) {
          final member = members[index];
          if (!moved.contains(member)) continue;
          if (previous != null) {
            final above = members[previous];
            final gap = index == previous + 1 ? before[member]!.dy - before[above]!.dy : 32.0;
            _positions[member] = Offset(_positions[member]!.dx, _positions[above]!.dy + gap);
          }
          previous = index;
        }
      }
    }
    closeVacatedStackSlots(_positions, before, moved, groups:_stacksBeforeDrop??_layout.stackGroups);
    _stacksBeforeDrop=null;
  }
  bool _selectionLifted=false;
  String? _selectionAnchor;
  void _startSelectionLift(Offset global,List<ElementRecord> records,List<({MemoBox box,Rect bounds})> regions){
    _rememberStacks();
    final scene=_sceneKey.currentContext?.findRenderObject() as RenderBox?;
    if(scene==null || !_canEdit)return;
    final point=scene.globalToLocal(global);
    final hit=_hitSelection(point,records);
    if(hit==null)return;
    setState((){
      _selected.removeWhere((id)=>!_positions.containsKey(id)&&!_tagPositions.containsKey(id));
      if(!_selected.contains(hit)){_selected..clear()..add(hit);}
      _selectionLifted=true;_movingSelection=true;_selectionAnchor=hit;
      _selectionStart=point;_selectionEnd=point;_selectionGlobalDown=global;
      _selectionDragOrigins..clear()..addEntries(_selected.map((id)=>MapEntry(id,_selectionPoint(id))));
      _liftBoxes..clear()..addEntries(regions.where((r)=>r.box.elementIds.any(_selected.contains)).map((r)=>MapEntry(r.box,r.bounds)));
    });
  }
  void _moveLiftedSelection(Offset global,List<ElementRecord> records){
    if(!_selectionLifted || _selectionGlobalDown==null || _selectionDragOrigins.isEmpty)return;
    _updateCanvas((){
      final delta=(global-_selectionGlobalDown!)/_view.value.storage[0].abs();
      final left=_selectionDragOrigins.values.map((p)=>p.dx).reduce(math.min),top=_selectionDragOrigins.values.map((p)=>p.dy).reduce(math.min);
      final shift=Offset(math.max(delta.dx,32-left),math.max(delta.dy,32-top));
      for(final entry in _selectionDragOrigins.entries){_setSelectionPoint(entry.key,entry.value+shift);}
      final target=_selectionHasPhoto ? null : records.where((r)=>!workspacePhotos.containsKey(r.id)&&!_selected.contains(r.id)&&_bounds(r.id).overlaps(_selectionBounds(_selectionAnchor!))).lastOrNull;
      _dropHighlights..clear()..addAll(target==null?<String>{}:alignedStackMembers(target.id,_positions,groups:_layout.stackGroups).difference(_selected));
    });
  }
  void _clearSelectionLift(){
    _selectionLifted=false;_liftBoxes.clear();_selectionAnchor=null;_dropHighlights.clear();
    _selectionStart=null;_selectionEnd=null;_movingSelection=false;_selectionDragOrigins.clear();
  }
  void _cancelSelectionLift(){
    if(!_selectionLifted)return;
    setState((){for(final e in _selectionDragOrigins.entries){_setSelectionPoint(e.key,e.value);}_clearSelectionLift();});
    _saveLayout(flush:true);
  }
  void _finishSelectionLift(Offset global,List<ElementRecord> records,List<({MemoBox box,Rect bounds})> regions,Map<String,Rect> folders){
    if(!_selectionLifted)return;
    setState((){
      final anchor=_selectionAnchor!;
      final origin=_selectionDragOrigins[anchor]!;
      if (!_positions.containsKey(anchor)) { _closeMovedSlots(_selectionDragOrigins); _clearSelectionLift(); return; }
      if((_positions[anchor]!-origin).distance<.5){_clearSelectionLift();return;}
      final scene=_sceneKey.currentContext?.findRenderObject() as RenderBox?;
      final point=scene?.globalToLocal(global)??_bounds(anchor).center;
      final target=_selectionHasPhoto ? null : records.where((r)=>!workspacePhotos.containsKey(r.id)&&!_selected.contains(r.id)&&_bounds(r.id).overlaps(_bounds(anchor))).lastOrNull;
      if (_dropIntoBox(point, _selected)) {
        // Membership was decided by the drop point.
      } else if(target!=null){_snapSelection(records);}
      else if(folders.values.any((bounds)=>bounds.contains(point))&&!regions.any((r)=>_inside(r.bounds,point))){
        for(final e in _selectionDragOrigins.entries){_setSelectionPoint(e.key,e.value);}
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('생각은 메모상자 안에 담아주세요. 폴더에는 직접 넣을 수 없습니다.')));
      }else{
        final shift=_selectionHasPhoto ? Offset.zero : snapThought(_bounds(anchor),records.where((r)=>!workspacePhotos.containsKey(r.id)&&!_selected.contains(r.id)).map((r)=>_bounds(r.id)),tolerance:(24/_view.value.storage[0].abs()).clamp(12,48));
        if(_selected.every((id)=>(_selectionPoint(id)+shift).dx>=32&&(_selectionPoint(id)+shift).dy>=32)){for(final id in _selected){_setSelectionPoint(id,_selectionPoint(id)+shift);}}
        _joinStack(_selected, null);
        var changed=false;final detached=<MemoBox>{};
        for(final entry in _liftBoxes.entries){
          if(!_inside(entry.value,point)){
            for(final id in _selected){changed=entry.key.elementIds.remove(id)||changed;}
            _emptyBoxBounds[entry.key]=entry.value;detached.add(entry.key);
          }
        }
        final targets=regions.where((r)=>!detached.contains(r.box)&&_inside(r.bounds,point)).toList()..sort((a,b)=>(a.bounds.width*a.bounds.height).compareTo(b.bounds.width*b.bounds.height));
        if(targets.isNotEmpty){for(final id in _selected){if (_positions.containsKey(id)) moveThoughtToBox(id,targets.first.box);}changed=true;}
        if(changed)_changed();
      }
      _closeMovedSlots(_selectionDragOrigins);
      _clearSelectionLift();_separateOverlappingBoxes();
    });
    _saveLayout(flush:true);
  }

  void _snapSelection(List<ElementRecord> records) {
    final anchor = _selectionAnchor;
    if (_selectionHasPhoto || !_movingSelection || _selectionStart == null || anchor == null || !_positions.containsKey(anchor)) return;
    final tolerance = (24 / _view.value.storage[0].abs()).clamp(12, 48).toDouble();
    _rememberStacks();
    final others = records.where((r) => !workspacePhotos.containsKey(r.id) && !_selected.contains(r.id)).toList();
    final target = others.where((r) => _bounds(r.id).overlaps(_bounds(anchor))).lastOrNull;
    if (target == null) {
      final shift = snapThought(_bounds(anchor), others.map((r) => _bounds(r.id)), tolerance: tolerance);
      if (_selected.any((id) => (_selectionPoint(id) + shift).dx < 32 || (_selectionPoint(id) + shift).dy < 32)) return;
      final allowed = _limitThoughtDrag(_selected, shift);
      for (final id in _selected) { _setSelectionPoint(id, _selectionPoint(id) + allowed); }
    } else {
      if (!_selectionLifted && _allRegionBoxes.any((box) => box.elementIds.any(_selected.contains))) {
        final stack = alignedStackMembers(target.id, Map.of(_positions)..removeWhere((id, _) => _selected.contains(id)), groups: _layout.stackGroups);
        var y = stack.map((id) => _positions[id]!.dy).reduce(math.max);
        for (final id in {..._layout.layers.where(_selected.contains), ..._selected}.where(_positions.containsKey)) {
          y += 32;
          final shift = Offset(_positions[target.id]!.dx, y) - _positions[id]!;
          if ((_limitThoughtDrag({id}, shift) - shift).distance > .001) return;
        }
      }
      _closeMovedSlots(_selectionDragOrigins, compactSelection: false);
      _selectionDragOrigins.clear();
      final stationary = Map.of(_positions)..removeWhere((id, _) => _selected.contains(id));
      final members = alignedStackMembers(target.id, stationary, groups: _layout.stackGroups);
      var top = members.map((id) => stationary[id]!.dy).reduce(math.max);
      final ordered = {..._layout.layers.where(_selected.contains), ..._selected};
      for (final id in ordered.where(_positions.containsKey)) {
        top += 32;
        _positions[id] = Offset(stationary[target.id]!.dx, top);
      }
    }
    _joinStack(_selected,target?.id);
    if (target != null) {
      final moved = _layout.layers.where(_selected.contains).toList();
      _layout.layers.removeWhere(_selected.contains); _layout.layers.addAll(moved);
      final box = memoBoxes.where((box) => !box.isUnclassified && box.elementIds.contains(target.id)).firstOrNull;
      for (final id in _selected) {
        if (box != null && _selectionLifted) { if (_positions.containsKey(id)) moveThoughtToBox(id, box); }
        else if (box == null && _selectionLifted) { for (final box in memoBoxes.where((box) => !box.isUnclassified)) { box.elementIds.remove(id); } }
      }
      _changed();
    }
  }
  String? _frontThought, _liftedLabel;
  Offset? _labelPointer;
  void _moveLabel(String id, Offset global) {
    if (!_canEdit) return;
    final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    if (scene == null) return;
    setState(() { _liftedLabel = id; _labelPointer = scene.globalToLocal(global); });
  }
  Future<void> _dropLabel(ElementRecord source, Offset global) async {
    final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    final point = scene?.globalToLocal(global);
    setState(() { _liftedLabel = null; _labelPointer = null; });
    if (!_canEdit || point == null) return;
    final candidates = _records
      ..sort((a,b) => _layout.layers.indexOf(a.id).compareTo(_layout.layers.indexOf(b.id)));
    final width=ThoughtLabel.width(context,source.indexLabel);
    final labelBounds=Rect.fromLTWH(point.dx-width/2,point.dy-12,width,ThoughtLabel.height(context,source.indexLabel));
    final targetId=labelOverlapTarget(labelBounds,[for(final r in candidates)(id:r.id,bounds:_bounds(r.id))]);
    if (targetId==null) return;
    final target = candidates.firstWhere((r)=>r.id==targetId);
    if (target.id != source.id && target.indexLabel.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 라벨이 있는 메모입니다. 기존 라벨을 옮기거나 지운 뒤 다시 시도해주세요.')));
      return;
    }
    final title = source.indexLabel, color = source.indexLabelColor;
    if (target.id != source.id) elements.update(source.text,source.text,indexLabel:'',tags:Set.of(source.tags),inlineLinks:source.inlineLinks);
    elements.update(target.text,target.text,indexLabel:title,indexLabelColor:color,tags:Set.of(target.tags),
      labelOnLeft:point.dx < _bounds(target.id).center.dx,inlineLinks:target.inlineLinks);
    _changed();
    try { await saveWorkspaceContent?.call(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('라벨 이동은 로컬에 저장했지만 서버에 저장하지 못했습니다. $e'))); }
  }
  @override
  Widget build(BuildContext context) => SaveShortcuts(onSave:_saveCanvas,child:_build(context));
  bool _savingCanvas=false;
  Future<void> _saveCanvas() async {
    if(_savingCanvas || !_canEdit)return;_savingCanvas=true;
    try { _saveLayout(flush:true);widget.onLayoutChanged?.call();widget.onChanged();if(widget.storage?.syncResource!=null){await widget.storage!.flush();await widget.storage!.syncResource!(_resource);}else{await widget.onSave?.call();}
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.storage?.lastSaveReplaced==true?'서버 최신 자료로 갱신했습니다.':'저장되었습니다.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('저장 또는 동기화에 실패했습니다. 로컬 자료는 유지됩니다. $e')));}
    finally {_savingCanvas=false;}
  }
  final _canvasUpdates = ValueNotifier<int>(0);
  bool _canvasFrameScheduled = false;
  Offset? _boxDragPointer;

  // Gesture state is applied synchronously for hit testing and the final drop.
  // Only the canvas subtree needs to render these intermediate positions.
  void _updateCanvas(VoidCallback update) {
    update();
    if (_canvasFrameScheduled) return;
    _canvasFrameScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _canvasFrameScheduled = false;
      if (mounted) _canvasUpdates.value++;
    });
  }

  Offset? _containerResizeOrigin;
  Rect? _containerResizeStart;
  List<Rect> _resizeObstacles = const [];

  Iterable<Rect> _containerResizeObstacles(String key) sync* {
    final isFolder = key.startsWith('folder:');
    final name = key.substring(key.indexOf(':') + 1);
    final parent = isFolder ? name
        : _allRegionBoxes.where((box) => box.name == name).firstOrNull?.folder;
    for (final box in _allRegionBoxes) {
      if (!isFolder && box.name == name) continue;
      if (isFolder && box.folder != null && memoFolderContains(name, box.folder!)) continue;
      final bounds = _boxBounds(box);
      if (bounds != null) yield bounds;
    }
    for (final entry in _folderGeometry().entries) {
      final folder = entry.key;
      if (parent != null && memoFolderContains(folder, parent)) continue;
      if (isFolder && memoFolderContains(name, folder)) continue;
      yield entry.value;
    }
  }

  Rect _limitContainerResize(Rect start, Rect requested, Iterable<Rect> obstacles) {
    var result = requested;
    for (final obstacle in obstacles) {
      if (!result.inflate(24).overlaps(obstacle)) continue;
      // Clamp the edge being dragged. Let the existing content bounds continue
      // to drive automatic growth when a child is moved independently.
      result = Rect.fromLTRB(
        obstacle.right <= start.left ? math.max(result.left, math.min(start.left, obstacle.right + 24)) : result.left,
        obstacle.bottom <= start.top ? math.max(result.top, math.min(start.top, obstacle.bottom + 24)) : result.top,
        obstacle.left >= start.right ? math.min(result.right, math.max(start.right, obstacle.left - 24)) : result.right,
        obstacle.top >= start.bottom ? math.min(result.bottom, math.max(start.bottom, obstacle.top - 24)) : result.bottom,
      );
    }
    return result;
  }

  Iterable<Widget> _containerResizeEdges(String key, Rect bounds) sync* {
    final hit = (8 / _view.value.storage[0].abs()).clamp(3.0, 18.0);
    for (final x in [-1, 0, 1]) {
      for (final y in [-1, 0, 1]) {
        if (x == 0 && y == 0) continue;
        final handle = Rect.fromLTWH(
          x < 0 ? bounds.left - hit / 2 : x > 0 ? bounds.right - hit / 2 : bounds.left + hit / 2,
          y < 0 ? bounds.top - hit / 2 : y > 0 ? bounds.bottom - hit / 2 : bounds.top + hit / 2,
          x == 0 ? bounds.width - hit : hit,
          y == 0 ? bounds.height - hit : hit,
        );
        yield Positioned.fromRect(
          key: ValueKey('resize-$key-$x-$y'),
          rect: handle,
          child: MouseRegion(
            cursor: x == 0 ? SystemMouseCursors.resizeUpDown
                : y == 0 ? SystemMouseCursors.resizeLeftRight
                : x == y ? SystemMouseCursors.resizeUpLeftDownRight
                : SystemMouseCursors.resizeUpRightDownLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _containerResizeOrigin = details.focalPoint;
                _containerResizeStart = bounds;
                _resizeObstacles = _containerResizeObstacles(key).toList();
              },
              onScaleUpdate: (details) {
                final origin = _containerResizeOrigin;
                final start = _containerResizeStart;
                if (origin == null || start == null || details.pointerCount != 1) return;
                final delta = (details.focalPoint - origin) / _view.value.storage[0].abs();
                if (delta == Offset.zero) return;
                final next = Rect.fromLTRB(
                  x < 0 ? (start.left + delta.dx).clamp(math.min(0.0, start.left), start.right - 120).toDouble() : start.left,
                  y < 0 ? (start.top + delta.dy).clamp(math.min(0.0, start.top), start.bottom - 64).toDouble() : start.top,
                  x > 0 ? math.max(start.left + 120, start.right + delta.dx) : start.right,
                  y > 0 ? math.max(start.top + 64, start.bottom + delta.dy) : start.bottom,
                );
                final limited = _limitContainerResize(start, next, _resizeObstacles);
                _updateCanvas(() => _layout.containerBounds[key] = limited);
              },
              onScaleEnd: (_) {
                _containerResizeOrigin = null;
                _containerResizeStart = null;
                _resizeObstacles = const [];
              },
            ),
          ),
        );
      }
    }
  }

  final _canvasMenu = MenuController();
  final _canvasMenuKey = GlobalKey();
  MemoBox? _canvasMenuBox;
  String? _canvasMenuFolder;
  bool _canvasOwnsBrowserMenu = false;
  bool _canvasHovered = false;

  void _setCanvasBrowserMenu(bool suppress) {
    if (!kIsWeb || _canvasOwnsBrowserMenu == suppress) return;
    _canvasOwnsBrowserMenu = suppress;
    unawaited(suppress ? BrowserContextMenu.disableContextMenu()
        : BrowserContextMenu.enableContextMenu());
  }

  List<Widget> _canvasMenuItems() {
    final box = _canvasMenuBox;
    final folder = _canvasMenuFolder;
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 32)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return [
      SubmenuButton(
        style: compact,
        menuChildren: [
          if (folder == null)
            MenuItemButton(
              style: compact,
              onPressed: () => _create(target: box, useFilter: false),
              child: const CreateMenuLabel(Icons.edit_note_rounded, '생각'),
            ),
          if (box == null && folder == null)
            MenuItemButton(
              style: compact,
              onPressed: _createBox,
              child: const CreateMenuLabel(Icons.inventory_2_outlined, '메모상자'),
            ),
          if (box == null && folder == null)
            MenuItemButton(
              style: compact,
              onPressed: () => createWorkspacePhoto(context, widget.storage, onChanged: _changed),
              child: const CreateMenuLabel(Icons.image_outlined, '사진'),
            ),
        ],
        child: const Text('추가'),
      ),
      if (box != null || folder != null)
        MenuItemButton(
          style: compact,
          onPressed: () {
            if (box != null) {
              _deleteCanvasBox(box);
            } else {
              _deleteCanvasFolder(folder!);
            }
          },
          child: Text('‘${box?.name ?? folder}’ 삭제', overflow: TextOverflow.ellipsis),
        ),
    ];
  }

  Widget _buildCanvas(BuildContext context, ColorScheme color) {
    final preview = _stackPreview;
    final layers = preview == null ? _layout.layers : List<String>.of(_layout.layers);
    if (preview != null) _insertStackLayer(layers, preview);
    final ranks = {for (var i = 0; i < layers.length; i++) layers[i]: i};
    final records = _records..sort(
      (a, b) => (ranks[a.id] ?? 0).compareTo(ranks[b.id] ?? 0),
    );
    if (_frontThought != null && preview == null) {
      final front = records.where((r) => r.id == _frontThought).firstOrNull;
      if (front != null) {
        records.remove(front);
        records.add(front);
      }
    }
    final visiblePositions = {
      for (final record in records)
        record.id: (record.id == preview?.moving ? null : preview?.positions[record.id]) ?? _positions[record.id]!,
    };
    final thoughtBounds = [
      for (final record in records) visiblePositions[record.id]! & _size(record.id),
    ];
    void stepLayers(bool up) => _editCanvasLayout(() {
      _frontThought = null;
      stepCanvasLayers(_layout.layers, _positions, _selected, up: up,
          groups: _layout.stackGroups, photos: workspacePhotos.keys.toSet(),
          bounds: {for (var i = 0; i < records.length; i++) records[i].id: thoughtBounds[i]});
    });
    final coveredThoughts = {
      for (final i in coveredCanvasItems(thoughtBounds)) records[i].id,
    };
    final labelExtent = records.where((r) => r.indexLabel.isNotEmpty).fold(180.0, (width, r) => math.max(width, ThoughtLabel.width(context, r.indexLabel) + 36));
    final tags = _hideTags ? <String>[] : (records.expand((r) => r.tags).toSet().toList()..sort());
    final tagPositions = <String, Offset>{for (final tag in tags) 'tag:$tag': _tagPositions['tag:$tag']!};
    final nodeRects = <String, Rect>{
      for (var i = 0; i < records.length; i++) records[i].id: thoughtBounds[i],
      for (final e in tagPositions.entries) e.key: _tagBounds(e.key),
    };
    var sceneWidth = math.max(3000.0, nodeRects.values.map((r) => r.right + labelExtent).fold(0.0, math.max));
    var sceneHeight = math.max(2200.0, nodeRects.values.map((r) => r.bottom + 100).fold(0.0, math.max));
    final regions = <({MemoBox box, Rect bounds})>[];
    final regionBoxes = _regionBoxes.toList();
    for (final box in regionBoxes) {
      final bounds = _regionBounds(box, _positions);
      if (bounds != null) regions.add((box: box, bounds: _frozenBoxBounds(box, hitTest: false) ?? bounds));
    }
    var emptyX = regions.map((r) => r.bounds.right + 80).fold(
      nodeRects.values.map((r) => r.right + 80).fold(640.0, math.max), math.max);
    for (final box in regionBoxes) {
      if (regions.any((region) => region.box == box)) continue;
      regions.add((box: box, bounds: _boxBounds(box) ?? _emptyBoxBounds.putIfAbsent(box, () => _placeEmptyBox(emptyX))));
      emptyX += 340;
    }
    regions.sort((a, b) => (b.bounds.width * b.bounds.height).compareTo(a.bounds.width * a.bounds.height));
    sceneWidth = regions.map((r) => r.bounds.right + 100).fold(sceneWidth, math.max);
    sceneHeight = regions.map((r) => r.bounds.bottom + 100).fold(sceneHeight, math.max);
    final folders = memoFolderRegions({for (final r in regions) r.box: r.bounds}, _layout.folderPositions, manualBounds: _layout.containerBounds);
    folders.addAll(_frozenFolders);
    if (!_filters.isEmpty) {
      folders.removeWhere((name, _) => !regions.any((r) => r.box.folder != null && memoFolderContains(name, r.box.folder!)));
    }
    sceneWidth = folders.values.map((r) => r.right + 100).fold(sceneWidth, math.max);
    sceneHeight = folders.values.map((r) => r.bottom + 100).fold(sceneHeight, math.max);
    return Stack(children: [Positioned.fill(child: LayoutBuilder(builder: (context, viewport) {
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
            _view.value = Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(viewport.maxWidth / 2 - (left + right) / 2 * scale,
              viewport.maxHeight / 2 - (top + bottom) / 2 * scale, 0);
          });
        }
        void openCanvasMenu(Offset globalPosition) {
          if (!_canEdit) return;
          final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
          final anchor = _canvasMenuKey.currentContext?.findRenderObject() as RenderBox?;
          if (scene == null || anchor == null) return;
          final point = scene.globalToLocal(globalPosition);
          if (nodeRects.values.any((bounds) => bounds.contains(point))) return;
          final box = regions.where((r) => r.bounds.contains(point)).lastOrNull;
          final folder = box == null
              ? folders.entries.where((f) => f.value.contains(point)).lastOrNull
              : null;
          if (box != null && _boxHeaderBounds(box.bounds).contains(point)) return;
          if (folder != null &&
              point.dy < folder.value.top + MemoFolderRegion.headerHeight) return;
          final position = anchor.globalToLocal(globalPosition);
          _canvasMenu.close();
          _canvasTapDown = null;
          setState(() {
            _canvasMenuBox = box?.box;
            _canvasMenuFolder = folder?.key;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _canEdit && _canvasMenuKey.currentContext != null) {
              _setCanvasBrowserMenu(true);
              _canvasMenu.open(position: position);
            }
          });
        }

        final canvas = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown:(event){
            if (_canvasMenu.isOpen && event.buttons == kPrimaryButton) {
              _canvasMenu.close();
            }
            if (event.buttons == kSecondaryMouseButton) {
              openCanvasMenu(event.position);
              return;
            }
            if (_canEdit && _activeCanvasPointers.isEmpty) {
              _gestureBefore = _captureCanvas();
            }
            _activeCanvasPointers.add(event.pointer);widget.storage?.canvasInteracting=true;if(_canvasTapPointer!=null){_canvasTapDown=null;return;}_canvasTapPointer=event.pointer;_canvasTapDown=event.position;},
          onPointerMove:(event){if(_canvasTapDown!=null&&(event.position-_canvasTapDown!).distance>4)_canvasTapDown=null;},
          onPointerCancel:(event){if (!_activeCanvasPointers.contains(event.pointer)) return;_pointerFinished(event.pointer);_canvasTapDown=null;_canvasTapPointer=null;},
          onPointerUp:(event){
            if (!_activeCanvasPointers.contains(event.pointer)) return;
            _pointerFinished(event.pointer);
            final click=_canvasTapPointer==event.pointer&&_canvasTapDown!=null;
            _canvasTapDown=null;_canvasTapPointer=null;
            if(!click||_selected.isEmpty)return;
            final scene=_sceneKey.currentContext?.findRenderObject() as RenderBox?;
            if(scene==null)return;final point=scene.globalToLocal(event.position);
            if(_hitSelection(point,records)==null)setState((){_selected.clear();_rangeAnchor=null;});
          },child:InteractiveViewer(key: _viewportKey,
        panEnabled: !_canEdit || !_rangeSelection, scaleEnabled: !_canEdit || !_rangeSelection,
        onInteractionEnd: (_) => _saveLayout(flush: true),
        transformationController: _view, scaleFactor: 1000, constrained: false, minScale: .15, maxScale: MediaQuery.sizeOf(context).width >= 760 ? 12 : 8,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: AbsorbPointer(absorbing: !_canEdit, child: RepaintBoundary(child: SizedBox(key: _sceneKey, width: sceneWidth, height: sceneHeight, child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: AnimatedBuilder(animation:_view,builder:(context,_)=>CustomPaint(key: const ValueKey('canvas-boundary'),
            painter: CanvasBoundaryPainter(color.outline.withValues(alpha: .7),scale:_view.value.getMaxScaleOnAxis())))))),
          for (final folder in folders.entries) MemoFolderRegion(key: ValueKey('folder-region-${folder.key}'), name: folder.key, bounds: folder.value,onDelete:_canEdit?()=>_deleteCanvasFolder(folder.key):null,
            highlighted: _liftedFolder == folder.key,
            onLiftStart: (pointer) => _liftFolder(folder.key, pointer),
            onLiftMove: (pointer) => _moveLiftedFolder(folder.key, pointer),
            onLiftEnd: (pointer) => _finishFolderLift(folder.key, pointer),
            onZoom: _zoomCanvas,
            onEnd: () {
              if (_draggedFolder == folder.key) {
                setState(() {
                  final beforeRelease = _folderGeometry()[folder.key]?.topLeft;
                  for (String? name = folder.key; name != null; name = memoFolderParent(name)) { _releaseFolder(name); }
                  if (beforeRelease != null) _moveSelectedTags(_folderGeometry()[folder.key]!.topLeft - beforeRelease);
                  _draggedFolder = null;
                });
              }
              _endPinch();
            }, onMove: (delta) => _updateCanvas(() {
              if (_pinchBase != null) return;
              _draggedFolder = folder.key;
              final shift = Offset(math.max(delta.dx, 32 - folder.value.left), math.max(delta.dy, 32 - folder.value.top));
              _moveFolder(folder.key, shift); _moveSelectedTags(shift); _saveLayout();
            })),
          for (final region in regions) MemoBoxRegion(key: ValueKey('box-region-${region.box.name}'), box: region.box, bounds: region.bounds,showLabel:false, highlighted: identical(_hoverBox, region.box) || identical(_liftedBox, region.box)),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Connections(
            nodeRects,
            {for (final r in records) r.id: {if (!_hideTags) ...r.tags.map((tag) => 'tag:$tag')}}, color.outlineVariant, {for (final tag in tags) 'tag:$tag': Color(hashtagColors[tag] ?? 0xFF90A4AE)})))),
          if (records.isEmpty && regions.isEmpty && folders.isEmpty) Positioned(left: 1400, top: 1000, child: TextButton.icon(onPressed: _create,
            icon: const Icon(Icons.add), label: Text(_query.isNotEmpty ? '일치하는 생각 없음 · 새 생각 만들기' : '첫 생각 만들기'))),
          for (final record in records) Positioned(key: ValueKey('canvas-card-slot-${record.id}'), left: visiblePositions[record.id]!.dx - ThoughtInteraction.hitPadding, top: visiblePositions[record.id]!.dy - ThoughtInteraction.hitPadding,
            child: ThoughtInteraction(key: ValueKey('canvas-thought-${record.id}'), size: _size(record.id), aspectRatio: workspacePhotos[record.id]?.aspectRatio, desktop: MediaQuery.sizeOf(context).width >= 760,
                groupLifted: _selectionLifted && _selected.contains(record.id),
                onLift: () => setState(() {
                  _liftedThought = record.id;
                  _liftBoxes..clear()..addEntries(regions.where((r) => r.box.elementIds.contains(record.id)).map((r) => MapEntry(r.box, r.bounds)));
                }),
                onActiveChanged: (active) => setState(() { if (active) {
                  _rememberStacks();
                  _thoughtDragOrigins.putIfAbsent(record.id, () => _positions[record.id]!);
                  _liftBoxes
                    ..clear()
                    ..addEntries(regions.where((region) => region.box.elementIds.contains(record.id))
                        .map((region) => MapEntry(region.box, region.bounds)));
                } _draggingId = active ? record.id : null; if (!active) { _hoverBox = null; _dropHighlights.clear(); _stackPreview = null; } }),
                onTap: () async {
                  if (_detailOpen) return;
                  if (_selectionMode) { setState(() => _toggleThoughtSelection(record.id)); return; }
                  _rangeAnchor=record.id; _detailOpen=true;
                  try {
                    if (workspacePhotos.containsKey(record.id)) {
                      await openWorkspacePhoto(context, record.id, widget.storage);
                    } else {
                      await showElementMetadata(context, record.text, canvasLayout: _layout);
                    }
                  }
                  finally { _detailOpen=false; }
                },
                onMove: (delta) => _updateCanvas(() { final previous = _positions[record.id]!; final p = previous + _limitThoughtDrag({record.id}, delta); _positions[record.id] = Offset(math.max(32, p.dx), math.max(32, p.dy));
                  _stackPreview = _findStackInsertion(record.id, records);
                  _dropHighlights.clear();
                  if (_stackPreview case final preview?) {
                    _dropHighlights.addAll(preview.members.where((id) => id != record.id));
                  }
                  final center = _bounds(record.id).center;
                  _hoverBox = _boxAt(center, where: (box) => !box.elementIds.contains(record.id));
                  _saveLayout(); }),
                onBorderTap: () {
                  if (_selectionMode) {
                    setState(() => _toggleThoughtSelection(record.id));
                  } else if (!_ctrlPressed && !_shiftPressed && _selected.isNotEmpty) {
                    _toggleSelection(false);
                  }
                },
                onResizeStart: () {
                  if (workspacePhotos.containsKey(record.id)) {
                    _resizingThought = record.id;
                  } else {
                    _beginResize(record.id);
                  }
                },
                fitSize: workspacePhotos.containsKey(record.id) ? null
                    : (horizontal,vertical)=>_fitThought(record,horizontal,vertical),
                onAutoResize: (size,shift)=>_resizeThought(record.id,size,shift,snap:false),
                onResize: (size,shift) {
                  if (workspacePhotos.containsKey(record.id)) {
                    _resizeCanvasPhoto(record.id, size, shift);
                  } else {
                    _resizeThought(record.id, size, shift);
                  }
                },
                onDrop: (pointer) {
                  final origin = _thoughtDragOrigins[record.id];
                  if (origin != null && (_positions[record.id]! - origin).distance < .5) {
                    _positions[record.id] = origin;
                    _dropHighlights.clear(); _liftBoxes.clear();
                    _saveLayout(flush: true);
                    return;
                  }
                  final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
                  final center = scene?.globalToLocal(pointer) ?? _bounds(record.id).center;
                  if (_dropIntoBox(center, [record.id])) {
                    _saveLayout(flush: true);
                    return;
                  }
                  _rememberStacks();
                  final insertion = _findStackInsertion(record.id, records);
                  final targetId = insertion?.target;
                  if (insertion != null) {
                    _positions.addAll(insertion.positions);
                    _insertStackLayer(_layout.layers, insertion);
                    // The projected positions already close the source slot.
                    _thoughtDragOrigins.remove(record.id);
                  } else if (!workspacePhotos.containsKey(record.id)) {
                    final snap = targetId == null
                      ? snapThought(_bounds(record.id), records.where((r) => !workspacePhotos.containsKey(r.id) && r.id != record.id).map((r) => _bounds(r.id)),
                          tolerance: (24 / _view.value.storage[0].abs()).clamp(12, 48))
                      : nextStackSlot(targetId, record.id, _positions) - _positions[record.id]!;
                    final snapped = _positions[record.id]! + _limitThoughtDrag({record.id}, snap);
                    if (snapped.dx >= 32 && snapped.dy >= 32) _positions[record.id] = snapped;
                  }
                  _joinStack([record.id], targetId);
                  if (targetId != null) {
                    if (insertion == null) {
                      _layout.layers.remove(record.id);
                      _layout.layers.add(record.id);
                    }
                    final box = memoBoxes.where((box) => !box.isUnclassified && box.elementIds.contains(targetId)).firstOrNull;
                    if (box != null && _liftedThought == record.id) { moveThoughtToBox(record.id, box); }
                    else if (box == null && _liftedThought == record.id) { for (final box in memoBoxes.where((box) => !box.isUnclassified)) { box.elementIds.remove(record.id); } }
                    _liftBoxes.clear(); _changed(); _saveLayout(flush: true);
                    return;
                  }
                  // A lift can remove a memo when dropped outside every box.
                  if (_liftedThought != record.id) { _saveLayout(flush: true); return; }
                  if (folders.values.any((bounds) => bounds.contains(center)) &&
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
                }, onEnd: () { setState(() { final resized = _resizingThought != null; _liftedThought = null; if (!resized) _closeMovedSlots(_thoughtDragOrigins); _resizingThought = null; _resizeNeighbors.clear(); _thoughtDragOrigins.remove(record.id); _dropHighlights.clear(); _stackPreview = null; _liftBoxes.clear(); if (!resized) _separateOverlappingBoxes(); _draggingId = null; _hoverBox = null; }); _saveLayout(flush: true); },
                child: Card(margin: EdgeInsets.zero,
                  clipBehavior: workspacePhotos.containsKey(record.id) ? Clip.antiAlias : Clip.none,
                  color: wordBackgroundColor(context, record.text),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: _dropHighlights.contains(record.id) || _draggingId == record.id || (!_rangeSelection && _selected.isEmpty && _linkHoverTarget == record.id) ? color.primary : color.outlineVariant, width: _dropHighlights.contains(record.id) ? 3 : 2)),
                  child: workspacePhotos.containsKey(record.id)
                  ? StoredThumbnail(key: ValueKey(record.id), id: record.id, owner: widget.storage?.owner, name: record.text)
                  : SizedBox(width: _size(record.id).width - 8, height: _size(record.id).height - 8, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: Padding(padding: const EdgeInsets.all(8), child: MemoCommentCount(id:record.id,builder:(context,commentCount)=>Row(crossAxisAlignment:coveredThoughts.contains(record.id)?CrossAxisAlignment.start:CrossAxisAlignment.center,children:[
                      if(AttachmentIndicators.hasAttachments(record)||commentCount>0)...[FittedBox(fit:BoxFit.scaleDown,child:AttachmentIndicators(record:record,commentCount:commentCount)),const SizedBox(width:4)],
                      Expanded(child:CanvasLinkText(text:record.text,links:record.inlineLinks,onLinkHover:(link)=>_hoverMemoLink(record.id,link),enabled:MediaQuery.sizeOf(context).width >= 760 && !_rangeSelection && _selected.isEmpty,style:TextStyle(color:wordColor(context,record.text)))),
                    ])))),
                    if (record.tags.isNotEmpty)
                      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 8, 8), child: Text(record.tags.map((tag) => '#$tag').join('  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
                    if (_layout.stacked && record.tags.isEmpty) const SizedBox(height: 24),
                  ])))),
            ),
          for (final record in records.where((r) => r.indexLabel.isNotEmpty)) Positioned(key: ValueKey('label-position-${record.id}'),
            left: _liftedLabel == record.id ? _labelPointer!.dx - ThoughtLabel.width(context, record.indexLabel) / 2 : math.max(0, _positions[record.id]!.dx + (record.labelOnLeft ? -ThoughtLabel.width(context, record.indexLabel) + 4 : _size(record.id).width - 4)),
            top: _liftedLabel == record.id ? _labelPointer!.dy - 12 : _positions[record.id]!.dy + 4, width: ThoughtLabel.width(context, record.indexLabel),
            child: GestureDetector(
              onLongPressStart: _canEdit && !workspacePhotos.containsKey(record.id) ? (d) => _moveLabel(record.id,d.globalPosition) : null,
              onLongPressMoveUpdate: _canEdit && !workspacePhotos.containsKey(record.id) ? (d) => _moveLabel(record.id,d.globalPosition) : null,
              onLongPressEnd: _canEdit && !workspacePhotos.containsKey(record.id) ? (d) => _dropLabel(record,d.globalPosition) : null,
              onLongPressCancel: () { if (_liftedLabel != null) setState(() { _liftedLabel=null;_labelPointer=null; }); },
              child: ThoughtLabel(key: ValueKey('thought-label-${record.id}'), record: record, movable: _canEdit,
              active: _frontThought == record.id,
              onHold: (held) => setState(() { if (held) { _frontThought = record.id; } else if (_frontThought == record.id) { _frontThought = null; } })))),
          for (final region in regions) Positioned.fromRect(
            key: ValueKey('box-header-slot-${region.box.name}'),
            rect: _boxHeaderBounds(region.bounds),
            child: Listener(
              onPointerDown: (event) => _boxDragPointer = event.position,
              child: GestureDetector(key: ValueKey('box-drag-header-${region.box.name}'), behavior: HitTestBehavior.opaque,
              onLongPressStart: (d) => _liftBox(region.box, d.globalPosition),
              onLongPressMoveUpdate: (d) => _moveLiftedBox(region.box, d.globalPosition),
              onLongPressEnd: (d) => _finishBoxDrag(region.box, d.globalPosition),
              onScaleStart: (details) => _boxDragPointer ??= details.focalPoint,
              onScaleUpdate: (details) {
                final previous = _boxDragPointer;
                _boxDragPointer = details.focalPoint;
                if (previous == null || details.pointerCount != 1) return;
                final scene = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
                if (scene == null) return;
                final delta = scene.globalToLocal(details.focalPoint) - scene.globalToLocal(previous);
                if (delta != Offset.zero) _updateCanvas(() => _dragBox(region.box, delta));
              },
              onScaleEnd: (details) {
                final pointer = _boxDragPointer;
                _boxDragPointer = null;
                if (pointer != null) _finishBoxDrag(region.box, pointer);
              },
              child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[Flexible(child:Text(region.box.name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:Color(region.box.color),fontSize:13,fontWeight:FontWeight.w600))),
                if(_canEdit&&!region.box.isUnclassified)IconButton(tooltip:'${region.box.name} 상자 삭제',onPressed:()=>_deleteCanvasBox(region.box),style:IconButton.styleFrom(minimumSize:const Size.square(24),padding:EdgeInsets.zero,tapTargetSize:MaterialTapTargetSize.shrinkWrap),icon:const Icon(Icons.close,size:16)),
              ])))),
          for (final tag in tags) Positioned(left: _tagBounds('tag:$tag').left, top: _tagBounds('tag:$tag').top,
            width: _tagBounds('tag:$tag').width, height: _tagBounds('tag:$tag').height,
            child: GestureDetector(key: ValueKey('graph-tag-$tag'), behavior: HitTestBehavior.opaque,
              // Use the same recognizer as cards: a pan recognizer can lose to
              // InteractiveViewer's scale recognizer and move the viewport instead.
              onScaleStart: (_) {},
              onScaleUpdate: (d) => _updateCanvas(() {
                if (d.pointerCount > 1) { _zoomCanvas(d.scale, d.focalPoint); return; }
                if (_pinchBase != null) return;
                // ScaleGestureRecognizer already reports delta in local scene coordinates.
                final p = _tagPositions['tag:$tag']! + d.focalPointDelta;
                _tagPositions['tag:$tag'] = Offset(p.dx.clamp(graphTagSize.width / 2 + 32, sceneWidth - graphTagSize.width / 2), p.dy.clamp(graphTagSize.height / 2 + 32, sceneHeight - graphTagSize.height / 2)); _saveLayout();
              }),
              onScaleEnd: (_) => _endPinch(),
              child: AnimatedScale(scale: _selectionLifted && _selected.contains('tag:$tag') ? 1.04 : 1, duration: const Duration(milliseconds: 100), child: Tooltip(message: '#$tag', child: Material(key:ValueKey('graph-tag-body-$tag'), shape: StadiumBorder(side: BorderSide(color: Color(hashtagColors[tag] ?? 0xFF90A4AE), width: 2.5)),
              color: Color.alphaBlend(Color(hashtagColors[tag] ?? 0xFF90A4AE).withValues(alpha: .3), color.surface),child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),child:Center(child:Text('#$tag',style:Theme.of(context).textTheme.labelLarge,maxLines:1,overflow:TextOverflow.ellipsis)))))))),
          if (preview != null)
            Positioned(
              left: preview.left,
              top: preview.top - 2,
              width: preview.width,
              child: IgnorePointer(child: ColoredBox(color: color.primary,
                child: const SizedBox(height: 3))),
            ),
          if (_rangeSelection || _selected.isNotEmpty) Positioned.fill(child: Listener(
            onPointerDown: (event) {
              if (_selectionPointers.isEmpty) {
                _selectionDown = event.localPosition; _selectionGlobalDown = event.position;
                _selectionBeforeGesture = Set.of(_selected);
              }
              if(_selectionPointers.isNotEmpty && _selectionLifted)_cancelSelectionLift();
              _selectionPointers[event.pointer] = event.position;
              _updateSelectionZoom();
            },
            onPointerMove: (event) { _selectionPointers[event.pointer] = event.position; _updateSelectionZoom(); },
            onPointerUp: (event) => _removeSelectionPointer(event.pointer),
            onPointerCancel: (event) => _removeSelectionPointer(event.pointer),
            child: GestureDetector(
            key: const ValueKey('canvas-selection'), behavior: HitTestBehavior.deferToChild, dragStartBehavior: DragStartBehavior.down,
            onLongPressStart:(d)=>_startSelectionLift(d.globalPosition,records,regions),
            onLongPressMoveUpdate:(d)=>_moveLiftedSelection(d.globalPosition,records),
            onLongPressEnd:(d)=>_finishSelectionLift(d.globalPosition,records,regions,folders),
            onLongPressCancel:_cancelSelectionLift,
            onTapUp: (d) => setState(() {
              final hit = _hitSelection(d.localPosition, records);
              if (hit != null && !_shiftPressed && _selected.contains(hit)) {
                _toggleThoughtSelection(hit); return;
              }
              if (!_selectionMode && !_shiftPressed && _selected.isNotEmpty) {
                _toggleSelection(false); return;
              }
              if (hit == null) { _selected.clear(); _rangeAnchor=null; _rangeAnchorPoint=null; }
              else if (_shiftPressed && _rangeAnchor != null && nodeRects.containsKey(_rangeAnchor)) {
                final range = Rect.fromPoints(_rangeAnchorPoint ?? _selectionBounds(_rangeAnchor!).center, d.localPosition).inflate(.5);
                for (var i=0;i<records.length;i++) {
                  if (selectsVisibleThought(range,_bounds(records[i].id),records.skip(i+1).map((r)=>_bounds(r.id)),radius:6)) _selected.add(records[i].id);
                }
                for(final id in tagPositions.keys){if(range.overlaps(nodeRects[id]!))_selected.add(id);}
              } else {
                if(_selectionMode){_toggleThoughtSelection(hit);}
                else{_selected..clear()..add(hit);}
                _rangeAnchor=hit; _rangeAnchorPoint=d.localPosition;
              }
            }),
            onScaleStart: (d) => setState(() {
              if (d.pointerCount > 1 || _selectionPinched) return;
              _rememberStacks();
              _selected.removeWhere((id) => !nodeRects.containsKey(id));
              final hit = _hitSelection(_selectionDown ?? d.localFocalPoint, records);
              _movingSelection = hit != null; _selectionAnchor = hit;
              if (hit != null && !_selected.contains(hit)) { _selected..clear()..add(hit); }
              _selectionStart = _selectionDown ?? d.localFocalPoint; _selectionEnd = d.localFocalPoint;
              if (!_movingSelection) { _selected.clear(); _rangeAnchor=null; _rangeAnchorPoint=null; }
              _selectionDragOrigins..clear()..addEntries(_selected.map((id) => MapEntry(id, _selectionPoint(id))));
              _liftBoxes
                ..clear()
                ..addEntries(regions.where((region) => region.box.elementIds.any(_selected.contains))
                    .map((region) => MapEntry(region.box, region.bounds)));
            }),
            onScaleUpdate: (d) => _updateCanvas(() {
              if (d.pointerCount > 1) {
                _selected..clear()..addAll(_selectionBeforeGesture);
                _selectionStart = null; _selectionEnd = null; return;
              }
              if (_selectionPinched || _selectionStart == null) return;
              if (_movingSelection) {
                if (_selectionPointers.isEmpty || _selectionGlobalDown == null || _selectionDragOrigins.isEmpty) return;
                _selectionEnd = d.localFocalPoint;
                final delta = (_selectionPointers.values.first - _selectionGlobalDown!) / _view.value.storage[0].abs();
                final left = _selectionDragOrigins.values.map((p) => p.dx).reduce(math.min);
                final top = _selectionDragOrigins.values.map((p) => p.dy).reduce(math.min);
                final shift = Offset(math.max(delta.dx, 32 - left), math.max(delta.dy, 32 - top));
                final anchor = _selectionDragOrigins.entries.first;
                final allowed = _limitThoughtDrag(_selected, anchor.value + shift - _selectionPoint(anchor.key));
                for (final id in _selectionDragOrigins.keys) { _setSelectionPoint(id, _selectionPoint(id) + allowed); }
                final target = _selectionHasPhoto ? null : records.where((r) => !workspacePhotos.containsKey(r.id) && !_selected.contains(r.id) && _selectionAnchor != null && _bounds(r.id).overlaps(_selectionBounds(_selectionAnchor!))).lastOrNull;
                _dropHighlights..clear()..addAll(target == null ? <String>{} : alignedStackMembers(target.id, _positions,groups:_layout.stackGroups).difference(_selected));
              } else {
                _selectionEnd = d.localFocalPoint;
                final rect = Rect.fromPoints(_selectionStart!, _selectionEnd!);
                _selected.clear();
                for(final id in tagPositions.keys){if(rect.overlaps(nodeRects[id]!))_selected.add(id);}
                for (var i = 0; i < records.length; i++) {
                  if (selectsVisibleThought(rect, _bounds(records[i].id), records.skip(i + 1).map((r) => _bounds(r.id)),
                      radius: 6)) { _selected.add(records[i].id); _rangeAnchor ??= records[i].id; _rangeAnchorPoint ??= _selectionStart; }
                }
              }
            }),
            onScaleEnd: (_) { setState(() {
              final drop = _selectionEnd;
              if (!_movingSelection || drop == null || drop == _selectionStart || !_dropIntoBox(drop, _selected)) {
                _snapSelection(records);
              }
              _closeMovedSlots(_selectionDragOrigins); _liftBoxes.clear(); _selectionAnchor = null; _dropHighlights.clear(); _selectionStart = null; _selectionEnd = null; _movingSelection = false; }); _endPinch(); },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: _selectionLifted ? 1.04 : 1),
              duration: const Duration(milliseconds: 100),
              builder: (context, scale, child) => CustomPaint(painter: _SelectionPainter(
              [for (final r in records) (rect: _bounds(r.id), selected: _selected.contains(r.id)), for(final id in tagPositions.keys)(rect:nodeRects[id]!,selected:_selected.contains(id))],
              !_movingSelection && _selectionStart != null && _selectionEnd != null ? Rect.fromPoints(_selectionStart!, _selectionEnd!) : null,
              color.primary, 6, captureAll: _rangeSelection, liftScale: scale, containerHeaders: [
                for (final region in regions) _boxHeaderBounds(region.bounds),
                for (final bounds in folders.values)
                  Rect.fromLTWH(bounds.left, bounds.top, bounds.width, MemoFolderRegion.headerHeight),
              ], resizeRects: {for(final r in records)_bounds(r.id)}))),
          ))),
          if (_canEdit && !_rangeSelection) ...[
            for (final folder in folders.entries)
              ..._containerResizeEdges('folder:${folder.key}', folder.value),
            for (final region in regions)
              ..._containerResizeEdges('box:${region.box.name}', region.bounds),
          ],
        ])))),
      ));
        if (!_canEdit) return canvas;
        return MouseRegion(
          onEnter: (_) {
            _canvasHovered = true;
            _setCanvasBrowserMenu(true);
          },
          onExit: (_) {
            _canvasHovered = false;
            if (!_canvasMenu.isOpen) _setCanvasBrowserMenu(false);
          },
          child: MenuAnchor(
            controller: _canvasMenu,
            onClose: () => _setCanvasBrowserMenu(_canvasHovered),
            menuChildren: _canvasMenuItems(),
            child: SizedBox.expand(
              key: _canvasMenuKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                supportedDevices: const {PointerDeviceKind.touch},
                onLongPressStart: (details) {
                  if (_activeCanvasPointers.length != 1) return;
                  openCanvasMenu(details.globalPosition);
                },
                child: canvas,
              ),
            ),
          ),
        );
      })),
        if (_canEdit && records.any((record) => _selected.contains(record.id) &&
            !workspacePhotos.containsKey(record.id)))
          Positioned(bottom: 8, left: 0, right: 0, child: Center(
            child: Material(
              color: color.surfaceContainerHigh,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: '선택한 생각 삭제',
                icon: const Icon(Icons.close),
                onPressed: () => _deleteSelectedThoughts({
                  for (final record in records)
                    if (_selected.contains(record.id) && !workspacePhotos.containsKey(record.id)) record.id,
                }),
              ),
            ),
          )),
        if (_canEdit && _selected.isNotEmpty) Positioned(top: 8, right: 12, child: Material(key: const ValueKey('canvas-layer-panel'),
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: IntrinsicWidth(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(style: IconButton.styleFrom(minimumSize: const Size(32, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), tooltip: '레이어 위로', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: () {
                stepLayers(true);
              }),
              IconButton(style: IconButton.styleFrom(minimumSize: const Size(32, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), tooltip: '레이어 아래로', icon: const Icon(Icons.arrow_downward, size: 18), onPressed: () {
                stepLayers(false);
              }),
            ]),
            if (_selected.length > 1) TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 24), padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.standard, textStyle: const TextStyle(fontSize: 11)),
              icon: const Icon(Icons.swap_vert, size: 15), label: const Text('순서 반전'), onPressed: () {
                _editCanvasLayout(() { reverseThoughtLayers(_layout.layers, _selected); reorderStackPositions(_positions, _selected,groups:_layout.stackGroups); alignStackLayers(_layout.layers, _positions, _layout.stackGroups); });
              }),
          ])),
        )),
        if (_canEdit) Positioned(top: 8, left: 4, child: Material(
          color: color.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 32, height: 36, child: Checkbox(
              visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: _selectionChecked, onChanged: (value) => _toggleSelection(value ?? false))),
            InkWell(onTap: () => _toggleSelection(!_selectionChecked), child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('선택', style: TextStyle(fontSize: 13)), const SizedBox(width: 4),
                SizedBox(width: 24, child: Text(_selected.isEmpty ? '' : '${_selected.length}', key: const ValueKey('selection-count'),
                  textAlign: TextAlign.left, style: const TextStyle(fontSize: 13))),
              ]))),
          ]),
        )),
    ]);
  }

  Widget _build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final actionWidth = math.max(0.0, MediaQuery.sizeOf(context).width - 76);
    return Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle(_filters.singleBox?.name ?? '전체 보기'), actions: [ConstrainedBox(
      constraints: BoxConstraints(maxWidth: actionWidth),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(36, 40), maximumSize: const Size(36, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const DesktopMenuAction(),
      if(widget.storage!=null)ValueListenableBuilder<String>(valueListenable:widget.storage!.canvasSaveState,builder:(context,state,_)=>Tooltip(message:state,child:Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Icon(state=='저장됨'?Icons.cloud_done_outlined:state=='저장 중'?Icons.cloud_upload_outlined:Icons.cloud_queue,size:18)))),
      if (_canEdit) ...[
        IconButton(tooltip: '실행 취소 (Ctrl+Z)', icon: const Icon(Icons.undo),
          onPressed: _undo.isEmpty ? null : () => _stepHistory(redo: false)),
        IconButton(tooltip: '다시 실행 (Ctrl+Y)', icon: const Icon(Icons.redo),
          onPressed: _redo.isEmpty ? null : () => _stepHistory(redo: true)),
      ],
      if(_canEdit)MemoBoxActions(onCreate:_createBox,onCreateThought:_create,
        onCreatePhoto: () => createWorkspacePhoto(
          context, widget.storage, box: _filterBox, onChanged: _changed)),
      IconButton(tooltip: '전체 보기', icon: const Icon(Icons.fit_screen_outlined),
        onPressed: () => setState(() => _centered = false)),
      PopupMenuButton<String>(style: IconButton.styleFrom(fixedSize: const Size(36, 40), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        enabled: _canEdit, tooltip: '정리하기', icon: const Icon(Icons.auto_awesome_motion_outlined),
        onSelected: (action) {
          if (action == 'space') {
            _compactBoxSpace();
          } else {
            _confirmResetArrangement(action == 'stack');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'space', child: Text('공간정리')),
          PopupMenuItem(value: 'spread', child: Text('펼쳐보기')),
          PopupMenuItem(value: 'stack', child: Text('겹쳐보기')),
        ]),
      IconButton(tooltip: '사용 안내', icon: const Icon(Icons.info_outline), onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('사용 안내'),
          content: const Text('생각·태그를 드래그해 배치하세요. 생각을 누르면 수정할 수 있습니다. 라벨을 누르는 동안 해당 생각을 앞으로 볼 수 있습니다.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))]))),
    ]))))]), body: DesktopMenuBody(child: Column(children: [
      if (widget.viewSelector != null) widget.viewSelector!,
      if (!_canEdit) const Padding(key:ValueKey('canvas-readonly-notice'),padding:EdgeInsets.all(4),child:Text('읽기 전용 워크스페이스입니다.')),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: Row(children: [
        Expanded(child: TextField(key: const ValueKey('graph-search'), controller: _search, focusNode: _searchFocus,
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
          decoration: const InputDecoration(hintText: '생각·해시태그 찾기', prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
          onChanged: (value) => setState(() { _query = value.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase(); _centered = false; _sync(); }))),
        ...[
          const SizedBox(width: 8),
          FilterChip(showCheckmark: false, visualDensity: VisualDensity.compact,
            label: const Text('해시태그 숨기기', style: TextStyle(fontSize: 12)), selected: _hideTags,
            onSelected: (value) => setState(() { _hideTags = value; if(value)_selected.removeWhere(_tagPositions.containsKey); _saveLayout(); })),
        ],
      ])),
      Expanded(child: ListenableBuilder(
        listenable: _canvasUpdates,
        builder: (context, _) => _buildCanvas(context, color),
      )),
      ThoughtFilters(tags: _scopeRecords.expand((r) => r.tags).toSet().toList()..sort(),
        selection: _filters, onChanged: _changed,
        onFilter: (box, tag) {
          if (tag != null && widget.onSearchTag != null) {
            widget.onSearchTag!(tag);
          } else {
            _filters.toggle(box, tag);
          }
        }),
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

    final cards = [
      for (final entry in positions.entries)
        if (!tagColors.containsKey(entry.key)) entry,
    ];
    final ranks = {for (var i = 0; i < cards.length; i++) cards[i].key: i};
    late final index = CanvasOverlapIndex([for (final entry in cards) entry.value]);
    for (final entry in links.entries) {
      final rank = ranks[entry.key];
      if (rank == null) continue;
      List<Rect>? covers;
      for (final id in entry.value) {
        if ((tagColors.containsKey(id) || entry.key.compareTo(id) < 0) && positions.containsKey(id) && positions.containsKey(entry.key)) {
          final card = positions[entry.key]!;
          final tag = positions[id]!;
          Offset? start = card.center;
          if (tagColors.containsKey(id) && (tag.center.dx < card.left || tag.center.dx > card.right)) {
            covers ??= index.overlappingAbove(rank);
            start = hashtagConnectionAnchor(card, covers, tag.center);
          }
          if (start == null) continue;
          final end = tag.center;
          final path = Path()..moveTo(start.dx, start.dy)..lineTo(end.dx, end.dy);
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
    !listEquals(positions.keys.toList(), oldDelegate.positions.keys.toList()) ||
    !mapEquals(tagColors, oldDelegate.tagColors) || links.length != oldDelegate.links.length ||
    links.entries.any((entry) => !setEquals(entry.value, oldDelegate.links[entry.key]));
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.selected, this.marquee, this.color, this.radius, {this.captureAll=false, this.liftScale=1, this.resizeRects=const {}, this.containerHeaders=const []});
  final List<Rect> containerHeaders;
  final Set<Rect> resizeRects;
  final double liftScale;
  final bool captureAll;
  @override
  bool hitTest(Offset position) {
    if (containerHeaders.any((rect) => rect.contains(position))) return false;
    for (final item in selected.reversed) {
      if (RRect.fromRectAndRadius(item.rect,Radius.circular(resizeRects.contains(item.rect)?radius:item.rect.shortestSide/2)).contains(position)) {
        // Let the visible frontmost card's resize handle receive border events.
        if(resizeRects.contains(item.rect)&&(!captureAll||item.selected)&&!item.rect.deflate(12).contains(position))return false;
        return true;
      }
    }
    return captureAll;
  }
  final double radius;
  final List<({Rect rect, bool selected})> selected;
  final Rect? marquee;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2 * liftScale;
    Rect paintedBounds(({Rect rect, bool selected}) item) => item.selected
      ? Rect.fromCenter(center: item.rect.center, width: item.rect.width * liftScale, height: item.rect.height * liftScale)
      : item.rect;
    for (var i = 0; i < selected.length; i++) {
      if (!selected[i].selected) continue;
      final bounds = paintedBounds(selected[i]);
      final itemRadius=resizeRects.contains(selected[i].rect)?radius:selected[i].rect.shortestSide/2;
      final visible = visibleThoughtPath(bounds,
        selected.skip(i + 1).map((item) => paintedBounds(item).inflate(.5)), radius: itemRadius * liftScale);
      canvas.save(); canvas.clipPath(visible);
      canvas.drawRRect(RRect.fromRectAndRadius(bounds.deflate(liftScale), Radius.circular(itemRadius * liftScale)), border);
      canvas.restore();
    }
    if (marquee != null) {
      canvas.drawRect(marquee!, Paint()..color = color.withValues(alpha: .12));
      canvas.drawRect(marquee!, border);
    }
  }
  @override
  bool shouldRepaint(_SelectionPainter old) =>
      color != old.color || radius != old.radius || liftScale != old.liftScale ||
      marquee != old.marquee || !listEquals(selected, old.selected) ||
      !setEquals(resizeRects, old.resizeRects);
}

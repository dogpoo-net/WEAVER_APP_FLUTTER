import 'dart:async';
import 'package:flutter/material.dart';

enum _Kind { project, paragraph, element, tag }
class _MenuDrag {
  const _MenuDrag(this.kind, this.index);
  final _Kind kind;
  final int index;
}

class WorkspaceMenu extends StatefulWidget {
  const WorkspaceMenu({super.key, required this.projects, this.tags = const [],
    this.paragraphs = const [], this.elements = const [], this.embedded = false,
    this.onSelected, this.onHide, this.onPin, this.folders = const [],
    this.projectFolderNames = const [], this.tagFolders = const [], this.tagFolderNames = const {},
    this.paragraphFolders = const [], this.elementFolders = const [],
    this.paragraphFolderNames = const [], this.elementFolderNames = const [],
    this.onProjectMoved, this.onTagMoved, this.onParagraphMoved, this.onElementMoved});
  final bool embedded;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onHide, onPin;
  static const createProject = -1000002, resetData = -1000003;
  static const createFolder = -1000000, createTagFolder = -1000001;
  static const createParagraphFolder = -1000004, createElementFolder = -1000005;
  static int paragraphChoice(int index) => -2000000 - index;
  static int elementChoice(int index) => -3000000 - index;
  final List<String> projects, paragraphs, elements, tags, folders, tagFolders, paragraphFolders, elementFolders;
  final List<String?> projectFolderNames, paragraphFolderNames, elementFolderNames;
  final Map<String, String> tagFolderNames;
  final void Function(int index, String? folder)? onProjectMoved, onParagraphMoved, onElementMoved;
  final void Function(String tag, String? folder)? onTagMoved;
  @override
  State<WorkspaceMenu> createState() => _WorkspaceMenuState();
}

class _WorkspaceMenuState extends State<WorkspaceMenu> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  late Map<_Kind, List<String?>> _placements;
  Timer? _autoScroll;
  Offset? _pointer;
  List<String> _items(_Kind kind) => switch (kind) {
    _Kind.project => widget.projects, _Kind.paragraph => widget.paragraphs,
    _Kind.element => widget.elements, _Kind.tag => widget.tags,
  };
  List<String> _folders(_Kind kind) => switch (kind) {
    _Kind.project => widget.folders, _Kind.paragraph => widget.paragraphFolders,
    _Kind.element => widget.elementFolders, _Kind.tag => widget.tagFolders,
  };
  String _label(_Kind kind) => switch (kind) {
    _Kind.project => '프로젝트', _Kind.paragraph => '문단', _Kind.element => '원소', _Kind.tag => '해시태그',
  };
  void _sync() {
    _placements = {for (final kind in _Kind.values) kind: List.generate(_items(kind).length, (i) {
      final names = switch (kind) {
        _Kind.project => widget.projectFolderNames, _Kind.paragraph => widget.paragraphFolderNames,
        _Kind.element => widget.elementFolderNames, _Kind.tag => <String?>[],
      };
      return kind == _Kind.tag ? widget.tagFolderNames[widget.tags[i]] : (i < names.length ? names[i] : null);
    })};
  }
  @override
  void initState() { super.initState(); _sync(); }
  @override
  void didUpdateWidget(WorkspaceMenu oldWidget) { super.didUpdateWidget(oldWidget); _sync(); }
  @override
  void dispose() { _autoScroll?.cancel(); _scroll.dispose(); super.dispose(); }
  void _select(int choice) {
    if (widget.onSelected != null) { widget.onSelected!(choice); }
    else { Navigator.pop(context, choice); }
  }
  void _startDrag() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final box = _viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || _pointer == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 40 ? -12.0 : y > box.size.height - 40 ? 12.0 : 0.0;
      if (delta != 0) _scroll.jumpTo((_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }
  Widget _item(_Kind kind, int index, {bool nested = false}) {
    final name = _items(kind)[index];
    final label = kind == _Kind.tag ? '#$name' : name.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final tile = ListTile(key: ValueKey('menu-${kind.name}-$index'),
      dense: kind == _Kind.tag,
      minVerticalPadding: kind == _Kind.tag ? 2 : null,
      visualDensity: kind == _Kind.tag ? const VisualDensity(vertical: -3) : null,
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: nested ? const TextStyle(fontSize: 13) : null),
      leading: Icon(switch (kind) { _Kind.tag => Icons.tag, _Kind.element => Icons.circle_outlined,
        _Kind.paragraph => Icons.subject, _Kind.project => Icons.article_outlined }, size: 20),
      onTap: () => _select(switch (kind) { _Kind.project => index, _Kind.tag => -3 - index,
        _Kind.paragraph => WorkspaceMenu.paragraphChoice(index), _Kind.element => WorkspaceMenu.elementChoice(index) }));
    final draggable = switch (kind) {
      _Kind.project => widget.onProjectMoved != null, _Kind.paragraph => widget.onParagraphMoved != null,
      _Kind.element => widget.onElementMoved != null, _Kind.tag => widget.onTagMoved != null,
    };
    if (!draggable) return tile;
    final data = _MenuDrag(kind, index);
    final feedback = Material(elevation: 6, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(label)));
    void update(DragUpdateDetails d) { _pointer = d.globalPosition; }
    void end(DraggableDetails _) { _autoScroll?.cancel(); _pointer = null; }
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    if (desktop) { return Draggable<_MenuDrag>(data: data, feedback: feedback, maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: .35, child: tile), onDragStarted: _startDrag,
      onDragUpdate: update, onDragEnd: end, child: tile); }
    return LongPressDraggable<_MenuDrag>(data: data, feedback: feedback, maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: .35, child: tile), onDragStarted: _startDrag,
      onDragUpdate: update, onDragEnd: end, child: tile);
  }
  Widget _target(_Kind kind, String? folder, Widget child) => DragTarget<_MenuDrag>(
    key: ValueKey('drop-${kind.name}-${folder ?? 'unfiled'}'),
    onWillAcceptWithDetails: (d) => d.data.kind == kind,
    onAcceptWithDetails: (d) {
      final index = d.data.index;
      setState(() => _placements[kind]![index] = folder);
      switch (kind) {
        case _Kind.project: widget.onProjectMoved?.call(index, folder);
        case _Kind.paragraph: widget.onParagraphMoved?.call(index, folder);
        case _Kind.element: widget.onElementMoved?.call(index, folder);
        case _Kind.tag: widget.onTagMoved?.call(widget.tags[index], folder);
      }
    },
    builder: (context, candidates, rejected) => Material(
      color: candidates.isEmpty ? Colors.transparent : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12), child: child),
  );
  Widget _heading(_Kind kind) => Padding(padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 4),
    child: Row(children: [
      Expanded(child: Text(_label(kind), style: Theme.of(context).textTheme.labelMedium)),
      if (kind == _Kind.project) IconButton(tooltip: '프로젝트 생성', visualDensity: VisualDensity.compact,
        iconSize: 18, onPressed: () => _select(WorkspaceMenu.createProject), icon: const Icon(Icons.add)),
      IconButton(tooltip: kind == _Kind.project ? '폴더 만들기' : '${_label(kind)} 폴더 만들기',
        visualDensity: VisualDensity.compact, iconSize: 18,
        onPressed: () => _select(switch (kind) {
          _Kind.project => WorkspaceMenu.createFolder, _Kind.tag => WorkspaceMenu.createTagFolder,
          _Kind.paragraph => WorkspaceMenu.createParagraphFolder, _Kind.element => WorkspaceMenu.createElementFolder,
        }), icon: const Icon(Icons.create_new_folder_outlined)),
    ]));
  List<Widget> _section(_Kind kind) {
    final folders = _folders(kind), items = _items(kind);
    final placements = _placements[kind]!;
    return [
      for (final folder in folders) _target(kind, folder, ExpansionTile(
        key: PageStorageKey('${kind.name}-$folder'), leading: const Icon(Icons.folder_outlined), title: Text(folder),
        childrenPadding: const EdgeInsetsDirectional.only(start: 16),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        collapsedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        expansionAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 200),
          reverseDuration: Duration(milliseconds: 200), curve: Curves.easeInOutCubic, reverseCurve: Curves.easeInOutCubic),
        children: [for (var i = 0; i < items.length; i++) if (placements[i] == folder) _item(kind, i, nested: true)],
      )),
      if (folders.isNotEmpty && kind != _Kind.project) _target(kind, null, const ListTile(dense: true,
        leading: Icon(Icons.folder_open_outlined, size: 18), title: Text('미분류'))),
      for (var i = 0; i < items.length; i++)
        if (placements[i] == null || !folders.contains(placements[i])) _item(kind, i),
      if (items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('아직 ${_label(kind)}가 없어요')),
    ];
  }
  @override
  Widget build(BuildContext context) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 4), child: Row(children: [
        const Expanded(child: Text('WEAVER', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2))),
        if (!widget.embedded && widget.onPin != null) IconButton(tooltip: '메뉴 고정하기', onPressed: widget.onPin,
          icon: const Icon(Icons.push_pin_outlined)),
        IconButton(tooltip: widget.embedded ? '메뉴 숨기기' : '메뉴 닫기',
          onPressed: widget.embedded ? widget.onHide : () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      ListTile(leading: const Icon(Icons.home_outlined), title: const Text('메인'), onTap: () => _select(-1)),
      const Divider(indent: 16, endIndent: 16),
      Expanded(child: SizedBox(key: _viewport, child: Scrollbar(controller: _scroll,
        child: CustomScrollView(controller: _scroll, key: const ValueKey('menu-projects'), slivers: [
          for (final kind in _Kind.values) SliverMainAxisGroup(slivers: [
            SliverPersistentHeader(pinned: true, delegate: _SectionHeading(kind: kind.name, child: kind == _Kind.project
              ? _target(kind, null, _heading(kind)) : _heading(kind))),
            SliverList(delegate: SliverChildListDelegate(_section(kind))),
          ]),
          const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
        ]),
      ))),
      const Divider(indent: 16, endIndent: 16),
      ListTile(dense: true, leading: const Icon(Icons.delete_outline, size: 18), title: const Text('데이터 초기화'),
        onTap: () => _select(WorkspaceMenu.resetData)),
    ]);
    if (widget.embedded) return Material(child: SizedBox(width: 280, child: content));
    return Dialog(alignment: AlignmentDirectional.topStart, insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
      child: SizedBox(width: 320, height: 480, child: content));
  }
}

class _SectionHeading extends SliverPersistentHeaderDelegate {
  const _SectionHeading({required this.kind, required this.child});
  final String kind;
  final Widget child;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(
    height: maxExtent, child: Material(key: ValueKey('menu-${kind}s-heading'),
      color: Theme.of(context).colorScheme.surface, child: child));
  @override
  bool shouldRebuild(_SectionHeading oldDelegate) => oldDelegate.child != child;
}

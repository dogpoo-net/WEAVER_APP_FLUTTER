import 'memo_boxes.dart';
import 'dart:async';
import 'tag_colors.dart';
import 'package:flutter/material.dart';

enum _Kind { project, paragraph, element, box, tag }
class _MenuDrag {
  const _MenuDrag(this.kind, this.index);
  final _Kind kind;
  final int index;
}

class WorkspaceMenu extends StatefulWidget {
  const WorkspaceMenu({super.key, required this.projects, this.tags = const [],
    this.paragraphs = const [], this.elements = const [], this.embedded = false,
    this.onSelected, this.onHide, this.onPin, this.onFloat, this.folders = const [],
    this.projectFolderNames = const [], this.tagFolders = const [], this.tagFolderNames = const {},
    this.paragraphFolders = const [], this.elementFolders = const [],
    this.paragraphFolderNames = const [], this.elementFolderNames = const [],
    this.onBoxChanged, this.onTagColorChanged, this.onProjectMoved, this.onTagMoved, this.onParagraphMoved, this.onElementMoved});
  final bool embedded;
  final VoidCallback? onBoxChanged;
  static const createBox = -1000007, createBoxFolder = -1000008;
  final VoidCallback? onTagColorChanged;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onHide, onPin, onFloat;
  static const allThoughts = -1000006, createParagraph = -2;
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
    _Kind.box => memoBoxes.map((box) => box.name).toList(), _Kind.element => widget.elements, _Kind.tag => widget.tags,
  };
  List<String> _folders(_Kind kind) => switch (kind) {
    _Kind.project => widget.folders, _Kind.paragraph => widget.paragraphFolders,
    _Kind.box => memoBoxFolders, _Kind.element => widget.elementFolders, _Kind.tag => widget.tagFolders,
  };
  String _label(_Kind kind) => switch (kind) {
    _Kind.project => '프로젝트', _Kind.paragraph => '문단', _Kind.box => '메모상자', _Kind.element => '생각', _Kind.tag => '해시태그',
  };
  void _sync() {
    _placements = {for (final kind in _Kind.values) kind: List.generate(_items(kind).length, (i) {
      final names = switch (kind) {
        _Kind.project => widget.projectFolderNames, _Kind.paragraph => widget.paragraphFolderNames,
        _Kind.box => memoBoxes.map((box) => box.folder).toList(), _Kind.element => widget.elementFolderNames, _Kind.tag => <String?>[],
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
        style: nested || kind == _Kind.project || kind == _Kind.paragraph || kind == _Kind.box ? const TextStyle(fontSize: 13) : null),
      trailing: kind == _Kind.tag ? IconButton(
        tooltip: '#$name 색상 변경',
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: const EdgeInsets.all(9),
        onPressed: () async {
          final current = hashtagColors[name];
          final color = await pickHashtagColor(context, name, current == null ? null : Color(current));
          if (!mounted || color == null) return;
          setState(() => hashtagColors[name] = color.toARGB32());
          widget.onTagColorChanged?.call();
        },
        icon: Container(width: 16, height: 16, decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hashtagColors.containsKey(name) ? Color(hashtagColors[name]!) : Theme.of(context).colorScheme.outlineVariant,
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .4)))),
      ) : kind == _Kind.box ? IconButton(tooltip: '$name 상자 색상 변경',
        icon: Icon(Icons.circle, size: 16, color: Color(memoBoxes[index].color)), onPressed: () async {
          final box = memoBoxes[index];
          final color = await pickHashtagColor(context, box.name, Color(box.color), prefix: '');
          if (!mounted || color == null) return;
          setState(() => box.color = color.toARGB32()); widget.onBoxChanged?.call();
        }) : null,
      leading: Icon(switch (kind) { _Kind.box => Icons.inventory_2_outlined, _Kind.tag => Icons.tag, _Kind.element => Icons.circle_outlined,
        _Kind.paragraph => Icons.subject, _Kind.project => Icons.article_outlined }, size: 20),
      onTap: () => _select(switch (kind) { _Kind.box => -1100000 - index, _Kind.project => index, _Kind.tag => -3 - index,
        _Kind.paragraph => WorkspaceMenu.paragraphChoice(index), _Kind.element => WorkspaceMenu.elementChoice(index) }));
    final draggable = switch (kind) {
      _Kind.project => widget.onProjectMoved != null, _Kind.paragraph => widget.onParagraphMoved != null,
      _Kind.box => true, _Kind.element => widget.onElementMoved != null, _Kind.tag => widget.onTagMoved != null,
    };
    if (!draggable) return tile;
    final child = kind == _Kind.box ? MemoBoxTarget(box: memoBoxes[index],
      onChanged: () { setState(() {}); widget.onBoxChanged?.call(); }, child: tile) : tile;
    final data = _MenuDrag(kind, index);
    final feedback = Material(elevation: 6, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(label)));
    void update(DragUpdateDetails d) { _pointer = d.globalPosition; }
    void end(DraggableDetails _) { _autoScroll?.cancel(); _pointer = null; }
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    if (desktop) { return Draggable<_MenuDrag>(data: data, feedback: feedback, maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: .35, child: tile), onDragStarted: _startDrag,
      onDragUpdate: update, onDragEnd: end, child: child); }
    return LongPressDraggable<_MenuDrag>(data: data, feedback: feedback, maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: .35, child: tile), onDragStarted: _startDrag,
      onDragUpdate: update, onDragEnd: end, child: child);
  }
  Widget _target(_Kind kind, String? folder, Widget child, {String? targetId}) => DragTarget<_MenuDrag>(
    key: ValueKey(targetId ?? 'drop-${kind.name}-${folder ?? 'unfiled'}'),
    onWillAcceptWithDetails: (d) => d.data.kind == kind,
    onAcceptWithDetails: (d) {
      final index = d.data.index;
      setState(() => _placements[kind]![index] = folder);
      switch (kind) {
        case _Kind.box: memoBoxes[index].folder = folder; widget.onBoxChanged?.call();
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
      if (kind == _Kind.box) IconButton(tooltip: '메모상자 만들기', iconSize: 18, visualDensity: VisualDensity.compact, icon: const Icon(Icons.add), onPressed: () => _select(WorkspaceMenu.createBox)),
      if (kind == _Kind.project || kind == _Kind.paragraph) IconButton(tooltip: kind == _Kind.project ? '프로젝트 생성' : '문단 추가', visualDensity: VisualDensity.compact,
        iconSize: 18, onPressed: () => _select(kind == _Kind.project ? WorkspaceMenu.createProject : WorkspaceMenu.createParagraph), icon: const Icon(Icons.add)),
      IconButton(tooltip: kind == _Kind.project ? '폴더 만들기' : '${_label(kind)} 폴더 만들기',
        visualDensity: VisualDensity.compact, iconSize: 18,
        onPressed: () => _select(switch (kind) {
          _Kind.box => WorkspaceMenu.createBoxFolder, _Kind.project => WorkspaceMenu.createFolder, _Kind.tag => WorkspaceMenu.createTagFolder,
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
      if (folders.isNotEmpty && kind == _Kind.element) _target(kind, null, const ListTile(dense: true,
        leading: Icon(Icons.folder_open_outlined, size: 18), title: Text('미분류'))),
      for (var i = 0; i < items.length; i++)
        if (placements[i] == null || !folders.contains(placements[i])) _item(kind, i),
      if (items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('아직 ${_label(kind)}${kind == _Kind.paragraph ? '이' : '가'} 없어요')),
      if (kind == _Kind.project || kind == _Kind.paragraph || kind == _Kind.box || kind == _Kind.tag)
        _target(kind, null, const SizedBox(height: 14, width: double.infinity),
          targetId: kind == _Kind.tag ? 'drop-tag-unfiled' : 'drop-${kind.name}-outside'),
    ];
  }
  @override
  Widget build(BuildContext context) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.embedded && MediaQuery.sizeOf(context).width >= 1000)
        Center(child: IconButton(tooltip: '메뉴 고정하기', onPressed: widget.onPin,
          icon: const Icon(Icons.push_pin_outlined))),
      if (MediaQuery.sizeOf(context).width < 1000) const SizedBox(height: 8),
      ListTile(dense: true, visualDensity: const VisualDensity(vertical: -2), leading: Icon(Icons.bubble_chart_outlined, size: MediaQuery.sizeOf(context).width < 1000 ? 20 : 19), title: Text('모든 생각 보기', style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 14 : 13)),
        trailing: IconButton(tooltip: '메뉴 닫기', icon: const Icon(Icons.close, size: 18),
          onPressed: widget.embedded ? widget.onHide : () => Navigator.pop(context)),
        onTap: () => _select(WorkspaceMenu.allThoughts)),
      const Divider(indent: 16, endIndent: 16),
      Expanded(child: SizedBox(key: _viewport, child: Scrollbar(controller: _scroll,
        child: CustomScrollView(controller: _scroll, key: const ValueKey('menu-projects'), slivers: [
          for (final kind in _Kind.values.where((kind) => kind != _Kind.element && kind != _Kind.paragraph)) SliverMainAxisGroup(slivers: [
            if (kind != _Kind.project) SliverToBoxAdapter(child: Divider(
              key: ValueKey('section-divider-${kind.name}'), height: 13, thickness: 1, indent: 20, endIndent: 20,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45))),
            SliverPersistentHeader(pinned: true, delegate: _SectionHeading(kind: kind.name,
              backgroundColor: widget.embedded ? Theme.of(context).colorScheme.surface
                  : (DialogTheme.of(context).backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHigh),
              child: (kind == _Kind.project || kind == _Kind.paragraph || kind == _Kind.box)
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
    return Dialog(alignment: AlignmentDirectional.topStart, insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 12),
      child: SizedBox(width: MediaQuery.sizeOf(context).width < 760 ? double.infinity : 320, height: double.infinity, child: content));
  }
}

class _SectionHeading extends SliverPersistentHeaderDelegate {
  const _SectionHeading({required this.kind, required this.child, required this.backgroundColor});
  final String kind;
  final Color backgroundColor;
  final Widget child;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(
    height: maxExtent, child: Material(key: ValueKey('menu-${kind}s-heading'),
      color: backgroundColor, child: child));
  @override
  bool shouldRebuild(_SectionHeading oldDelegate) => oldDelegate.child != child || oldDelegate.backgroundColor != backgroundColor;
}

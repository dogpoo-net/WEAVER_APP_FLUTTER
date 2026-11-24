import 'label_links.dart';
import 'tag_colors.dart';
import 'memo_boxes.dart';
import 'memo_box_actions.dart';
import 'package:flutter/material.dart';

class _DocumentDrag implements InlineLinkDragSource {
  const _DocumentDrag(this.index, this.linkKey);
  final int index;
  @override final String? linkKey;
}

class WorkspaceMenuViewState {
  final expandedFolders = <String>{};
  double scrollOffset = 0;
  int collapseRevision = 0;
}

class WorkspaceMenu extends StatefulWidget {
  const WorkspaceMenu({super.key, required this.projects, this.projectIds = const [], this.tags = const [],
    this.paragraphs = const [], this.elements = const [], this.embedded = false,
    this.viewState, this.onSelected, this.onHide, this.onPin, this.onFloat, this.folders = const [],
    this.projectFolderNames = const [], this.tagFolders = const [], this.tagFolderNames = const {},
    this.paragraphFolders = const [], this.elementFolders = const [],
    this.paragraphFolderNames = const [], this.elementFolderNames = const [],
    this.onRenameDocument, this.onRename, this.onBoxChanged, this.canMoveBoxes = false, this.onDeleteFolder, this.onDeleteDocument, this.onDeleteBox, this.onDeleteBoxFolder, this.onTagColorChanged, this.onProjectMoved, this.onTagMoved, this.onParagraphMoved, this.onElementMoved});
  final WorkspaceMenuViewState? viewState;
  final List<String> projectIds;
  final Future<void> Function(String id, String name)? onRenameDocument;
  final Future<void> Function(String kind, String oldName, String newName)? onRename;
  static const refresh = -1000011;
  final Future<void> Function(String kind, String folder)? onDeleteFolder;
  final Future<void> Function(String id)? onDeleteDocument;
  final Future<void> Function(String name, ContainerDeletion choice)? onDeleteBox;
  final Future<void> Function(String name, ContainerDeletion choice)? onDeleteBoxFolder;
  final bool embedded, canMoveBoxes;
  final VoidCallback? onBoxChanged;
  static const createBox = -1000007, createBoxFolder = -1000008;
  final VoidCallback? onTagColorChanged;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onHide, onPin, onFloat;
  static const allThoughts = -1000006, createParagraph = -2;
  static const home = -1000010, search = -1000012;
  static const documents = -1000013, thoughts = -1000014;
  static const hashtags = -1000015;
  static const memoBoxTab = -1000017;
  static const geolog = -1000016;
  static int boxChoice(int index) => -1100000 - index;
  static const settings = -1000009;
  static const createProject = -1000002, trash = -1000003;
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
  static final _boxButtonStyle = IconButton.styleFrom(
    fixedSize: const Size(32, 34),
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  late final _expanded = widget.viewState?.expandedFolders ?? <String>{};

  void _toggle(String key) => setState(() {
    if (!_expanded.add(key)) _expanded.remove(key);
  });

  static EdgeInsetsDirectional _treePadding(int depth) =>
      EdgeInsetsDirectional.only(start: 16.0 + 16 * depth, end: 4);

  Iterable<Widget> _boxTree(MemoBox? parent, int depth) sync* {
    for (final box in childMemoBoxes(parent)) {
      final key = 'memo-box:${box.name}';
      final hasChildren = childMemoBoxes(box).isNotEmpty;
      final expanded = hasChildren && _expanded.contains(key);
      final hasActions = widget.canMoveBoxes || widget.onRename != null || widget.onDeleteBox != null;
      final tile = ListTile(
        dense: true,
        minTileHeight: 34,
        contentPadding: _treePadding(depth + 1),
        leading: const Icon(Icons.inventory_2_outlined, size: 17),
        title: Text(box.name, overflow: TextOverflow.ellipsis),
        onTap: () => _select(WorkspaceMenu.boxChoice(memoBoxes.indexOf(box))),
        trailing: hasChildren || hasActions
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                if (hasChildren)
                  IconButton(
                    style: _boxButtonStyle,
                    tooltip: '${box.name} 하위 상자 ${expanded ? '접기' : '펼치기'}',
                    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
                    onPressed: () => _toggle(key),
                  ),
                if (hasActions) _boxActions(box),
              ])
            : null,
      );
      if (widget.canMoveBoxes) {
        yield DragTarget<MemoBox>(
          onWillAcceptWithDetails: (details) =>
              memoBoxes.contains(details.data) && canMoveMemoBox(details.data, box),
          onAcceptWithDetails: (details) {
            setState(() {
              details.data.folder = box.name;
              _expanded.add(key);
            });
            widget.onBoxChanged?.call();
          },
          builder: (context, candidates, _) {
            final child = ColoredBox(
              color: candidates.isEmpty ? Colors.transparent
                  : Theme.of(context).colorScheme.secondaryContainer,
              child: tile,
            );
            final feedback = Material(
              elevation: 4,
              child: Padding(padding: const EdgeInsets.all(10), child: Text(box.name)),
            );
            return MediaQuery.sizeOf(context).width < 760
                ? LongPressDraggable<MemoBox>(data: box, feedback: feedback, child: child)
                : Draggable<MemoBox>(data: box, feedback: feedback, child: child);
          },
        );
      } else {
        yield tile;
      }
      if (expanded) yield* _boxTree(box, depth + 1);
    }
  }

  Widget _boxActions(MemoBox box) => PopupMenuButton<String>(
    style: _boxButtonStyle,
    padding: EdgeInsets.zero,
    tooltip: '${box.name} 관리',
    icon: const Icon(Icons.more_vert, size: 16),
    onSelected: (action) => _manageBox(box, action),
    itemBuilder: (_) => [
      if (widget.canMoveBoxes)
        const PopupMenuItem(value: 'color', child: Text('색상')),
      if (widget.onRename != null)
        const PopupMenuItem(value: 'rename', child: Text('이름 변경')),
      if (widget.onDeleteBox != null)
        const PopupMenuItem(value: 'delete', child: Text('상자 삭제')),
    ],
  );

  Future<void> _manageBox(MemoBox box, String action) async {
    final name = box.name;
    try {
      switch (action) {
        case 'color':
          final color = await pickHashtagColor(context, name, Color(box.color), prefix: '');
          if (!mounted || color == null || !memoBoxes.contains(box)) return;
          box.color = color.toARGB32();
          widget.onBoxChanged?.call();
        case 'rename':
          var draft = name;
          final next = await showDialog<String>(context: context, builder: (context) {
            void submit() {
              if (draft.trim().isNotEmpty) Navigator.pop(context, draft.trim());
            }
            return AlertDialog(
              title: const Text('이름 변경'),
              content: TextFormField(
                initialValue: name, autofocus: true,
                decoration: const InputDecoration(labelText: '이름'),
                onChanged: (value) => draft = value,
                onFieldSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                TextButton(onPressed: submit, child: const Text('변경')),
              ],
            );
          });
          if (!mounted || next == null || next == name || !memoBoxes.contains(box)) return;
          await widget.onRename?.call('box', name, next);
          if (_expanded.remove('memo-box:$name')) _expanded.add('memo-box:$next');
        case 'delete':
          final choice = await confirmContainerDeletion(context, name);
          if (!mounted || choice == null || !memoBoxes.contains(box)) return;
          await widget.onDeleteBox?.call(name, choice);
          _expanded.remove('memo-box:$name');
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('상자 변경을 완료하지 못했습니다. $error')),
        );
      }
    }
  }

  void _refreshDocuments() {
    if (!mounted) return;
    if (widget.embedded) { setState(() {}); }
    else { Navigator.pop(context, WorkspaceMenu.refresh); }
  }

  Widget? _documentActions(String name, {String? id, bool folder = false}) {
    final rename = folder ? widget.onRename != null : id != null && widget.onRenameDocument != null;
    final delete = folder ? widget.onDeleteFolder != null : id != null && widget.onDeleteDocument != null;
    if (!rename && !delete) return null;
    return PopupMenuButton<String>(
      tooltip: '$name 관리', style: _boxButtonStyle,
      icon: const Icon(Icons.more_vert, size: 16),
      itemBuilder: (_) => [
        if (rename) const PopupMenuItem(value: 'rename', child: Text('이름 변경')),
        if (delete) PopupMenuItem(value: 'delete', child: Text(folder ? '폴더 삭제' : '문서 삭제')),
      ],
      onSelected: (action) async {
        try {
          if (action == 'rename') {
            var draft = name;
            final next = await showDialog<String>(context: context, builder: (context) {
              void submit() { if (draft.trim().isNotEmpty) Navigator.pop(context, draft.trim()); }
              return AlertDialog(title: const Text('이름 변경'),
                content: TextFormField(initialValue: name, autofocus: true,
                  onChanged: (value) => draft = value, onFieldSubmitted: (_) => submit()),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                  TextButton(onPressed: submit, child: const Text('변경'))]);
            });
            if (!mounted || next == null || next == name) return;
            if (folder) {
              await widget.onRename!('projectFolder',name,next);
              if (_expanded.remove('project-$name')) _expanded.add('project-$next');
            } else { await widget.onRenameDocument!(id!,next); }
          } else {
            final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
              title: Text(folder ? '폴더를 삭제할까요?' : '문서를 삭제하시겠어요?'),
              content: Text(folder ? '$name 폴더의 문서는 미분류로 이동합니다.' : name),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                TextButton(onPressed: () => Navigator.pop(context,true), child: const Text('삭제'))]));
            if (!mounted || yes != true) return;
            if (folder) { await widget.onDeleteFolder!('project',name); _expanded.remove('project-$name'); }
            else { await widget.onDeleteDocument!(id!); }
          }
          _refreshDocuments();
        } catch (error) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('변경을 저장하지 못했습니다. $error')));
        }
      },
    );
  }

  Widget _documentTarget(String? folder, Widget child) => DragTarget<_DocumentDrag>(
    key: ValueKey('drop-project-${folder ?? 'outside'}'),
    onWillAcceptWithDetails: (_) => widget.onProjectMoved != null && widget.canMoveBoxes,
    onAcceptWithDetails: (details) {
      widget.onProjectMoved!(details.data.index, folder);
      if (folder == null) _expanded.add('document-tree');
      _refreshDocuments();
    },
    builder: (context, candidates, _) => ColoredBox(color: candidates.isEmpty
        ? Colors.transparent : Theme.of(context).colorScheme.secondaryContainer, child: child),
  );

  Widget _document(int index) {
    final name = widget.projects[index];
    final id = index < widget.projectIds.length ? widget.projectIds[index] : null;
    final tile = ListTile(key: ValueKey('menu-project-$index'), dense: true,
      contentPadding: _treePadding(1),
      minTileHeight: 34, leading: const Icon(Icons.description_outlined, size: 17),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _documentActions(name, id: id), onTap: () => _select(index));
    final data = _DocumentDrag(index, id == null ? null : 'project:$id');
    final feedback = Material(elevation: 4, child: Padding(padding: const EdgeInsets.all(8), child: Text(name)));
    if (MediaQuery.sizeOf(context).width < 760) {
      return LongPressDraggable<_DocumentDrag>(data: data, feedback: feedback, child: tile);
    }
    return Draggable<_DocumentDrag>(data: data, feedback: feedback, child: tile);
  }

  Widget _treeToggle(String key, String label) => IconButton(
    style: _boxButtonStyle,
    tooltip: '$label 목록 ${_expanded.contains(key) ? '접기' : '펼치기'}',
    icon: Icon(_expanded.contains(key) ? Icons.expand_less : Icons.expand_more, size: 18),
    onPressed: () => _toggle(key),
  );

  Widget _createRow(String label, int action) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9DBDF0)
        : const Color(0xFF416A9C);
    return ListTile(
      textColor: color,
      iconColor: color,
      dense: true,
      minTileHeight: 34,
      contentPadding: _treePadding(1),
      leading: const Icon(Icons.add, size: 17),
      title: Text(label),
      onTap: () => _select(action),
    );
  }

  Widget _documentHeader() => _documentTarget(null, ListTile(contentPadding: _treePadding(0), dense: true, minTileHeight: 34,
      leading: const Icon(Icons.description_outlined, size: 22), title: const Text('문서'),
      onTap: () => _select(WorkspaceMenu.documents),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.canMoveBoxes) IconButton(style: _boxButtonStyle, tooltip: '폴더 만들기', icon: const Icon(Icons.create_new_folder_outlined, size: 17),
          onPressed: () => _select(WorkspaceMenu.createFolder)),
        _treeToggle('document-tree', '문서'),
      ])));
  Iterable<Widget> _documents() sync* {
    if (!_expanded.contains('document-tree')) return;
    String? folderAt(int i) => i < widget.projectFolderNames.length ? widget.projectFolderNames[i] : null;
    for (final folder in widget.folders) {
      yield _documentTarget(folder, ExpansionTile(key: ValueKey('project-$folder'), minTileHeight: 34, dense: true,
        tilePadding: _treePadding(1),
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: _expanded.contains('project-$folder'),
        onExpansionChanged: (open) { if (open) { _expanded.add('project-$folder'); } else { _expanded.remove('project-$folder'); } },
        leading: const Icon(Icons.folder_outlined, size: 17), title: Text(folder),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Builder(builder: (context) {
            final controller = ExpansibleController.of(context);
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) => IconButton(
                style: _boxButtonStyle,
                tooltip: '$folder 목록 ${controller.isExpanded ? '접기' : '펼치기'}',
                icon: Icon(controller.isExpanded ? Icons.expand_less : Icons.expand_more, size: 16),
                onPressed: controller.toggle,
              ),
            );
          }),
          if (_documentActions(folder, folder: true) case final actions?) actions,
        ]),
        childrenPadding: const EdgeInsetsDirectional.only(start: 16),
        children: [for (var i = 0; i < widget.projects.length; i++) if (folderAt(i) == folder) _document(i)]));
    }
    for (var i = 0; i < widget.projects.length; i++) {
      if (!widget.folders.contains(folderAt(i))) yield _document(i);
    }
    if (widget.canMoveBoxes) yield _createRow('문서 생성', WorkspaceMenu.createProject);
  }

  Widget _treeSection(Widget header, List<Widget> rows) =>
      SliverMainAxisGroup(slivers: [
        PinnedHeaderSliver(child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: header,
        )),
        SliverList.list(children: rows),
      ]);

  void _select(int choice) {
    if (widget.onSelected case final callback?) {
      callback(choice);
    } else {
      Navigator.pop(context, choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrowMenu = MediaQuery.sizeOf(context).width < 760;
    final showPin = widget.embedded ? widget.onFloat != null : widget.onPin != null;
    final navigationStyle = TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      minimumSize: const Size(0, 34),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const RoundedRectangleBorder(),
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
    );
    Widget navigationButton(String label, IconData icon, int destination, {double end = 16}) =>
        TextButton(
          style: navigationStyle.copyWith(
            padding: WidgetStatePropertyAll(EdgeInsetsDirectional.fromSTEB(16, 4, end, 4)),
          ),
          onPressed: () => _select(destination),
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ]),
        );
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.embedded && !narrowMenu) const SizedBox(height: 8),
      Stack(fit: StackFit.passthrough, children: [
        navigationButton('기록함', Icons.home_outlined, WorkspaceMenu.home, end: showPin ? 92 : 64),
        PositionedDirectional(top: 0, bottom: 0, end: 4, child: Center(
          child: IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
            iconSize: 18, padding: const EdgeInsets.all(5),
            minimumSize: const Size(28, 28), maximumSize: const Size(28, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )), child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (showPin)
              IconButton(tooltip: widget.embedded ? '메뉴 고정 해제' : '메뉴 고정하기',
                onPressed: widget.embedded ? widget.onFloat : widget.onPin,
                icon: Icon(widget.embedded ? Icons.push_pin : Icons.push_pin_outlined)),
            IconButton(tooltip: '메뉴 닫기', icon: const Icon(Icons.close),
              onPressed: widget.embedded ? widget.onHide : () => Navigator.pop(context)),
          ])),
        )),
      ]),
      navigationButton('검색', Icons.search, WorkspaceMenu.search),
      navigationButton('문서', Icons.description_outlined, WorkspaceMenu.documents),
      navigationButton('생각', Icons.bubble_chart_outlined, WorkspaceMenu.thoughts),
      navigationButton('지오로그', Icons.location_on_outlined, WorkspaceMenu.geolog),
      navigationButton('해시태그', Icons.tag, WorkspaceMenu.hashtags),
      const Divider(indent: 16, endIndent: 16),
      Expanded(child: CustomScrollView(
        slivers: [
          _treeSection(DragTarget<MemoBox>(
            onWillAcceptWithDetails: (details) => widget.canMoveBoxes &&
                memoBoxes.contains(details.data) && details.data.folder != null &&
                canMoveMemoBox(details.data, null),
            onAcceptWithDetails: (details) {
              setState(() {
                details.data.folder = null;
                _expanded.add('memo-box-tree');
              });
              widget.onBoxChanged?.call();
            },
            builder: (context, candidates, _) => ColoredBox(
              color: candidates.isEmpty ? Colors.transparent
                  : Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
            dense: true,
            minTileHeight: 34,
            contentPadding: _treePadding(0),
            leading: const Icon(Icons.inventory_2_outlined, size: 20),
            title: const Text('메모상자'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _treeToggle('memo-box-tree', '메모상자'),
            ]),
            onTap: () => _select(WorkspaceMenu.memoBoxTab),
          ))),
          [if (_expanded.contains('memo-box-tree')) ...[
            ..._boxTree(null, 0),
            if (widget.canMoveBoxes) _createRow('메모상자 만들기', WorkspaceMenu.createBox),
          ]]),
          _treeSection(_documentHeader(), _documents().toList()),
        ],
      )),
      const Divider(indent: 16, endIndent: 16),
      ListTile(dense: true, minTileHeight:36,minVerticalPadding:0,visualDensity:const VisualDensity(vertical:-2), leading: const Icon(Icons.delete_outline, size: 18), title: const Text('휴지통'),
        onTap: () => _select(WorkspaceMenu.trash)),
      ListTile(dense: true, minTileHeight:36,minVerticalPadding:0,visualDensity:const VisualDensity(vertical:-2), leading: const Icon(Icons.settings_outlined, size: 18), title: const Text('설정'),
        onTap: () => _select(WorkspaceMenu.settings)),
    ]);
    if (widget.embedded) return Material(child: SizedBox(width: 280, child: content));
    return Dialog(
      alignment: AlignmentDirectional.topStart,
      insetPadding: EdgeInsets.fromLTRB(16, narrowMenu ? 48 : 64, 16, 12),
      child: SizedBox(
        width: narrowMenu ? double.infinity : 320,
        height: double.infinity,
        child: narrowMenu
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: content,
              )
            : content,
      ),
    );
  }
}

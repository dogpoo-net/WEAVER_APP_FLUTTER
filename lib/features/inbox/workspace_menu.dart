import 'dart:async';

import 'package:flutter/material.dart';

class _MenuDrag {
  const _MenuDrag(this.tag, this.index);
  final bool tag;
  final int index;
}

class WorkspaceMenu extends StatefulWidget {
  const WorkspaceMenu({
    super.key,
    required this.projects,
    this.tags = const [],
    this.embedded = false,
    this.onSelected,
    this.onHide,
    this.onPin,
    this.folders = const [],
    this.projectFolderNames = const [],
    this.tagFolders = const [],
    this.tagFolderNames = const {},
    this.onProjectMoved,
    this.onTagMoved,
  });
  final bool embedded;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onHide, onPin;
  static const createFolder = -1000000;
  static const createTagFolder = -1000001;
  final List<String> folders, tags, projects, tagFolders;
  final List<String?> projectFolderNames;
  final Map<String, String> tagFolderNames;
  final void Function(int index, String? folder)? onProjectMoved;
  final void Function(String tag, String? folder)? onTagMoved;
  @override
  State<WorkspaceMenu> createState() => _WorkspaceMenuState();
}

class _WorkspaceMenuState extends State<WorkspaceMenu> {
  late List<String?> _projects;
  late Map<String, String> _tags;
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  Timer? _autoScroll;
  Offset? _pointer;
  void _sync() {
    _projects = List.generate(
      widget.projects.length,
      (i) => i < widget.projectFolderNames.length
          ? widget.projectFolderNames[i]
          : null,
    );
    _tags = Map.of(widget.tagFolderNames);
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WorkspaceMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _select(int choice) {
    if (widget.onSelected != null) {
      widget.onSelected!(choice);
    } else {
      Navigator.pop(context, choice);
    }
  }

  void _startDrag() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final box = _viewport.currentContext?.findRenderObject();
      if (box is! RenderBox || _pointer == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 40
          ? -12.0
          : y > box.size.height - 40
          ? 12.0
          : 0.0;
      if (delta != 0) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  Widget _item(bool tag, int index) {
    final label = tag ? '#${widget.tags[index]}' : widget.projects[index];
    final tile = ListTile(
      key: ValueKey('menu-${tag ? 'tag' : 'project'}-$index'),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: Icon(tag ? Icons.tag : Icons.article_outlined, size: 20),
      onTap: () => _select(tag ? -3 - index : index),
    );
    if ((tag ? widget.onTagMoved : widget.onProjectMoved) == null) return tile;
    final data = _MenuDrag(tag, index);
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(label)),
    );
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (desktop) {
      return Draggable<_MenuDrag>(
        data: data,
        feedback: feedback,
        maxSimultaneousDrags: 1,
        childWhenDragging: Opacity(opacity: .35, child: tile),
        onDragStarted: _startDrag,
        onDragUpdate: (d) => _pointer = d.globalPosition,
        onDragEnd: (_) {
          _autoScroll?.cancel();
          _pointer = null;
        },
        child: tile,
      );
    }
    return LongPressDraggable<_MenuDrag>(
      data: data,
      feedback: feedback,
      maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: .35, child: tile),
      onDragStarted: _startDrag,
      onDragUpdate: (d) => _pointer = d.globalPosition,
      onDragEnd: (_) {
        _autoScroll?.cancel();
        _pointer = null;
      },
      child: tile,
    );
  }

  Widget _target(bool tag, String? folder, Widget child) =>
      DragTarget<_MenuDrag>(
        key: ValueKey('drop-${tag ? 'tag' : 'project'}-${folder ?? 'unfiled'}'),
        onWillAcceptWithDetails: (d) => d.data.tag == tag,
        onAcceptWithDetails: (d) {
          final index = d.data.index;
          setState(() {
            if (tag) {
              final name = widget.tags[index];
              if (folder == null) {
                _tags.remove(name);
              } else {
                _tags[name] = folder;
              }
              widget.onTagMoved?.call(name, folder);
            } else {
              _projects[index] = folder;
              widget.onProjectMoved?.call(index, folder);
            }
          });
        },
        builder: (context, candidates, rejected) => Material(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      );
  Widget _heading(bool tag) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            tag ? '해시태그' : '프로젝트 ${widget.projects.length}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        IconButton(
          tooltip: tag ? '해시태그 폴더 만들기' : '폴더 만들기',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => _select(
            tag ? WorkspaceMenu.createTagFolder : WorkspaceMenu.createFolder,
          ),
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
    ),
  );
  List<Widget> _section(bool tag) {
    final folders = tag ? widget.tagFolders : widget.folders;
    final count = tag ? widget.tags.length : widget.projects.length;
    String? assigned(int i) => tag ? _tags[widget.tags[i]] : _projects[i];
    return [
      for (final folder in folders)
        _target(
          tag,
          folder,
          ExpansionTile(
            key: PageStorageKey('${tag ? 'tag' : 'project'}-$folder'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder),
            children: [
              for (var i = 0; i < count; i++)
                if (assigned(i) == folder) _item(tag, i),
            ],
          ),
        ),
      if (folders.isNotEmpty)
        _target(
          tag,
          null,
          const ListTile(
            dense: true,
            leading: Icon(Icons.folder_open_outlined, size: 18),
            title: Text('미분류'),
          ),
        ),
      for (var i = 0; i < count; i++)
        if (assigned(i) == null || !folders.contains(assigned(i)))
          _item(tag, i),
      if (count == 0)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tag ? '아직 해시태그가 없어요' : '아직 프로젝트가 없어요'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'WEAVER',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
              if (!widget.embedded && widget.onPin != null)
                IconButton(
                  tooltip: '메뉴 고정하기',
                  onPressed: widget.onPin,
                  icon: const Icon(Icons.push_pin_outlined),
                ),
              IconButton(
                tooltip: widget.embedded ? '메뉴 숨기기' : '메뉴 닫기',
                onPressed: widget.embedded
                    ? widget.onHide
                    : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: const Text('메인'),
          onTap: () => _select(-1),
        ),
        ListTile(
          leading: const Icon(Icons.subject),
          title: const Text('문단 쓰기'),
          onTap: () => _select(-2),
        ),
        const Divider(indent: 16, endIndent: 16),
        _heading(false),
        Expanded(
          child: SizedBox(
            key: _viewport,
            child: Scrollbar(
              controller: _scroll,
              child: ListView(
                controller: _scroll,
                key: const ValueKey('menu-projects'),
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  ..._section(false),
                  const Divider(indent: 16, endIndent: 16),
                  _heading(true),
                  ..._section(true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) {
      return Material(child: SizedBox(width: 280, child: content));
    }
    return Dialog(
      alignment: AlignmentDirectional.topStart,
      insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
      child: SizedBox(width: 320, height: 480, child: content),
    );
  }
}

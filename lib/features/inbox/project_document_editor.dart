import 'workspace_routes.dart';
import 'desktop_menu_frame.dart';
import 'package:flutter/material.dart';
import 'project_page.dart';
import 'paragraph_editor.dart';
import 'project_folders.dart';
import 'element_store.dart';
import 'word_badge.dart';

class ProjectDocumentEditor extends StatefulWidget {
  const ProjectDocumentEditor({super.key, this.project, this.onChanged});
  final WritingProject? project;
  final Future<void> Function()? onChanged;
  @override
  State<ProjectDocumentEditor> createState() => _ProjectDocumentEditorState();
}
class _ProjectDocumentEditorState extends State<ProjectDocumentEditor> {
  late final TextEditingController _name, _body;
  final _search = TextEditingController();
  final _references = <String>{}, _tags = <String>{};
  bool _dirty = false, _panelOpen = false;
  final _thoughtScroll = ScrollController(), _tagScroll = ScrollController(), _documentScroll = ScrollController();
  bool get _wide => MediaQuery.sizeOf(context).width >= 800;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name ?? '');
    _body = TextEditingController(text: widget.project?.document ?? widget.project?.paragraphs.map((p) =>
      '${p.role == ParagraphRole.title ? '# ' : p.role == ParagraphRole.subtitle ? '## ' : ''}${p.text}').join('\n\n') ?? '');
    _references.addAll(widget.project?.words ?? []);
    if (widget.project != null) { if (widget.project!.document == null) _references.addAll(elements.matches(_body.text).map((h) => h.word)); elements.indexProject(widget.project!); }
    _tags.addAll(widget.project?.tags ?? {});
    if (widget.project?.document == null) _tags.addAll(widget.project?.paragraphs.expand((p) => p.tags) ?? <String>[]);
    _name.addListener(_edited); _body.addListener(_edited); elements.addListener(_refresh);
  }
  void _edited() { if (mounted) setState(() => _dirty = true); }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { elements.removeListener(_refresh); _name.dispose(); _body.dispose(); _search.dispose(); _thoughtScroll.dispose(); _tagScroll.dispose(); _documentScroll.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('프로젝트 이름과 본문을 입력해주세요.'))); return;
    }
    final project = widget.project ?? WritingProject([], [], name: _name.text.trim());
    // The original paragraphs and their bindings remain intact in storage.
    project.document = _body.text; project.name = _name.text.trim();
    project.words..clear()..addAll(_references); project.tags..clear()..addAll(_tags);
    if (widget.project == null) { Navigator.pop(context, project); return; }
    elements.indexProject(project); await widget.onChanged?.call();
    if (mounted) { setState(() => _dirty = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.'))); }
  }
  Widget _referencesPanel() {
    final tags = {...elements.tags, ..._tags}.toList()..sort();
    final query = _search.text.trim().replaceFirst('#', '').toLowerCase();
    final thoughts = elements.records.values.where((r) =>
      _references.contains(r.text) || r.tags.any(_tags.contains)).toList();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: Scrollbar(controller: _thoughtScroll, child: SingleChildScrollView(
        key: const ValueKey('project-thought-scroll'), controller: _thoughtScroll, primary: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('연결된 생각', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (thoughts.isEmpty) Text('해시태그를 선택하면 관련 생각이 표시됩니다.', style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final r in thoughts)
            WordBadge(word: r.text, onTap: () => showElementMetadata(context, r.text),
              onLongPress: _references.contains(r.text) ? () => setState(() { _references.remove(r.text); _dirty = true; }) : null)]),
        ])))),
      const VerticalDivider(width: 20, thickness: 1),
      SizedBox(width: _wide ? 160 : 140, child: Column(children: [
        TextField(controller: _search, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: '해시태그 찾기', isDense: true, prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 32))),
        const SizedBox(height: 8),
        Expanded(child: Scrollbar(controller: _tagScroll, child: ListView(key: const ValueKey('project-tag-scroll'), controller: _tagScroll, primary: false, children: [
          for (final tag in tags.where((tag) => tag.toLowerCase().contains(query)))
            CheckboxListTile(key: ValueKey('project-tag-$tag'), dense: true, contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading, title: Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis),
              value: _tags.contains(tag), onChanged: (yes) => setState(() {
                if (yes == true) { _tags.add(tag); } else { _tags.remove(tag); } _dirty = true;
              })),
        ]))),
      ])),
    ]);
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_dirty, onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('변경 내용을 저장하지 않고 나갈까요?'), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 작성')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기'))]));
    if (discard == true && mounted) { setState(() => _dirty = false); WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) Navigator.pop(context); }); }
  }, child: Scaffold(appBar: AppBar(title: Text(widget.project?.name ?? '프로젝트 만들기'), actions: [const DesktopHomeAction(), const DesktopMenuAction(), TextButton(onPressed: _save, child: const Text('저장')),
    if (widget.project != null) IconButton(tooltip: '프로젝트 폴더', icon: const Icon(Icons.folder_outlined), onPressed: () async {
      final folder = await showDialog<String>(context: context, builder: (context) => SimpleDialog(title: const Text('프로젝트 폴더'), children: [for (final folder in ['', ...projectFolders])
        SimpleDialogOption(onPressed: () => Navigator.pop(context, folder), child: Text(folder.isEmpty ? '폴더 밖으로' : folder))]));
      if (folder != null) { widget.project!.folder = folder.isEmpty ? null : folder; await widget.onChanged?.call(); }
    })]), bottomNavigationBar: _wide ? null : Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: FilledButton.tonalIcon(key: const ValueKey('project-panel-toggle'),
          onPressed: () => setState(() => _panelOpen = !_panelOpen),
          icon: Icon(_panelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
          label: Text(_panelOpen ? '참고 패널 숨기기' : '참고 패널 올리기'))))), body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final document = Column(children: [TextField(key: const ValueKey('project-name'), controller: _name, decoration: const InputDecoration(labelText: '프로젝트 이름')),
        const SizedBox(height: 12), Expanded(child: TextField(key: const ValueKey('project-document'), controller: _body, scrollController: _documentScroll, expands: true, minLines: null, maxLines: null,
          textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: '연결된 생각을 참고하며 자유롭게 글을 써보세요.', border: OutlineInputBorder())))]);
      final panel = Padding(padding: const EdgeInsets.all(12), child: _referencesPanel());
      return Padding(padding: const EdgeInsets.all(16), child: _wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: document), const SizedBox(width: 20),
          SizedBox(key: const ValueKey('project-reference-panel'), width: (constraints.maxWidth * .45).clamp(400.0, 560.0),
            child: Material(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), child: panel))])
        : Column(children: [Expanded(child: document), AnimatedSize(duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic,
          child: _panelOpen ? SizedBox(key: const ValueKey('project-reference-panel'), height: (constraints.maxHeight * .42).clamp(0.0, 360.0), child: panel) : const SizedBox.shrink())]));
    }))));
}

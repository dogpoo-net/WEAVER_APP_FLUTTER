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
  bool _dirty = false;
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
  void dispose() { elements.removeListener(_refresh); _name.dispose(); _body.dispose(); _search.dispose(); super.dispose(); }
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('연결된 생각', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (thoughts.isEmpty) Text('해시태그를 선택하면 관련 생각이 표시됩니다.', style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final r in thoughts)
        WordBadge(word: r.text, onTap: () => showElementMetadata(context, r.text),
          onLongPress: _references.contains(r.text) ? () => setState(() { _references.remove(r.text); _dirty = true; }) : null)]),
      const Divider(height: 24),
      TextField(controller: _search, onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '해시태그 찾기', prefixIcon: Icon(Icons.search))),
      const SizedBox(height: 8),
      for (final tag in tags.where((tag) => tag.toLowerCase().contains(query)))
        CheckboxListTile(key: ValueKey('project-tag-$tag'), dense: true, contentPadding: EdgeInsets.zero,
          title: Text('#$tag'), value: _tags.contains(tag), onChanged: (yes) => setState(() {
            if (yes == true) { _tags.add(tag); } else { _tags.remove(tag); } _dirty = true;
          })),
    ]);
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_dirty, onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('변경 내용을 저장하지 않고 나갈까요?'), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 작성')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기'))]));
    if (discard == true && mounted) { setState(() => _dirty = false); WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) Navigator.pop(context); }); }
  }, child: Scaffold(appBar: AppBar(title: Text(widget.project?.name ?? '프로젝트 만들기'), actions: [TextButton(onPressed: _save, child: const Text('저장')),
    if (widget.project != null) IconButton(tooltip: '프로젝트 폴더', icon: const Icon(Icons.folder_outlined), onPressed: () async {
      final folder = await showDialog<String>(context: context, builder: (context) => SimpleDialog(title: const Text('프로젝트 폴더'), children: [for (final folder in ['', ...projectFolders])
        SimpleDialogOption(onPressed: () => Navigator.pop(context, folder), child: Text(folder.isEmpty ? '폴더 밖으로' : folder))]));
      if (folder != null) { widget.project!.folder = folder.isEmpty ? null : folder; await widget.onChanged?.call(); }
    })]), body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final document = Column(children: [TextField(key: const ValueKey('project-name'), controller: _name, decoration: const InputDecoration(labelText: '프로젝트 이름')),
        const SizedBox(height: 12), Expanded(child: TextField(key: const ValueKey('project-document'), controller: _body, expands: true, minLines: null, maxLines: null,
          textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: '연결된 생각을 참고하며 자유롭게 글을 써보세요.', border: OutlineInputBorder())))]);
      return Padding(padding: const EdgeInsets.all(16), child: constraints.maxWidth >= 800
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: document), const SizedBox(width: 20), SizedBox(width: 300, child: SingleChildScrollView(child: _referencesPanel()))])
        : Column(children: [Expanded(child: document), SizedBox(height: constraints.maxHeight * .28, child: SingleChildScrollView(child: _referencesPanel()))]));
    }))));
}

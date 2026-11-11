import 'thought_settings.dart';
import 'thought_filters.dart';
import 'label_links.dart';
import 'document_markup.dart';
import 'caret_assist.dart';
import 'keyboard_dismiss.dart';
import 'workspace_routes.dart';
import 'desktop_menu_frame.dart';
import 'package:flutter/material.dart';
import 'project_page.dart';
import 'paragraph_editor.dart';
import 'element_store.dart';
import 'word_badge.dart';

class ProjectDocumentEditor extends StatefulWidget {
  const ProjectDocumentEditor({super.key, this.project, this.onChanged, this.projects = const []});
  final WritingProject? project;
  final List<WritingProject> projects;
  final Future<void> Function()? onChanged;
  @override
  State<ProjectDocumentEditor> createState() => _ProjectDocumentEditorState();
}
class _ProjectDocumentEditorState extends State<ProjectDocumentEditor> {
  late final LabelTextController _body;
  bool _preview = false;
  final _search = TextEditingController();
  final _bodyFocus = FocusNode();
  final _tags = <String>{};
  final _filters = ThoughtFilterSelection();
  bool _dirty = false, _boxPanelOpen = false, _thoughtPanelOpen = true, _keyboardVisible = false;
  final _thoughtScroll = ScrollController(), _documentScroll = ScrollController();
  bool get _wide => MediaQuery.sizeOf(context).width >= 800;
  @override
  void initState() {
    super.initState();
    _body = LabelTextController( widget.project?.document ?? widget.project?.paragraphs.map((p) =>
      p.role == ParagraphRole.title ? '======${p.text}======' : p.role == ParagraphRole.subtitle ? '=====${p.text}=====' : p.text).join('\n\n') ?? '', widget.project?.documentLinks ?? const []);
    for (final project in widget.projects) { elements.indexProject(project); }
    if (widget.project != null) elements.indexProject(widget.project!);
    _tags.addAll(widget.project?.tags ?? {});
    if (widget.project?.document == null) _tags.addAll(widget.project?.paragraphs.expand((p) => p.tags) ?? <String>[]);
    _filters.tags.addAll(_tags); _filters.addListener(_refresh);
    _body.addListener(_edited); elements.addListener(_refresh);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (visible && !_keyboardVisible) _boxPanelOpen = false;
    _keyboardVisible = visible;
  }
  void _edited() { if (mounted) setState(() => _dirty = true); }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { elements.removeListener(_refresh); _body.dispose(); _bodyFocus.dispose(); _search.dispose(); _thoughtScroll.dispose(); _filters.dispose(); _documentScroll.dispose(); super.dispose(); }
  void _insertLabel(String word) {
    _body.insertTarget(word); _bodyFocus.requestFocus();
  }
  void _insertTag(String tag) {
    final token = tagPrefix(_body.value);
    if (token.isEmpty) return;
    final end = _body.selection.end;
    _body.value = TextEditingValue(text: _body.text.replaceRange(end - token.length, end, '#$tag '),
      selection: TextSelection.collapsed(offset: end - token.length + tag.length + 2));
    _tags.add(tag); _bodyFocus.requestFocus();
  }
  Future<void> _save() async {
    _body.completeLinks();
    _tags.addAll(cleanLinkedInput(_body).tags);
    if (_body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본문을 입력해주세요.'))); return;
    }
    final project = widget.project ?? WritingProject([], [], name: documentTitle(_body.text));
    // The original paragraphs and their bindings remain intact in storage.
    project.document = _body.text; project.name = documentTitle(_body.text);
    project.documentLinks = List.of(_body.bindings);
    project.words.clear(); project.tags..clear()..addAll({..._tags, ..._filters.tags});
    if (widget.project == null) { Navigator.pop(context, project); return; }
    elements.indexProject(project); await widget.onChanged?.call();
    if (mounted) { setState(() => _dirty = false); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장했습니다.'))); }
  }
  Widget _referencesPanel() {
    final query = _search.text.trim().replaceFirst('#', '').toLowerCase();
    final thoughts = elements.records.values.where((r) => canBrowseThought(r) && _filters.matches(r) &&
      (r.text.toLowerCase().contains(query) || r.indexLabel.toLowerCase().contains(query) || r.tags.any((tag) => tag.contains(query)))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(key: const ValueKey('project-reference-search'), controller: _search,
        onTapOutside: _wide ? null : (_) {},
        style: const TextStyle(fontSize: 12), onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: '생각·해시태그 찾기', isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), prefixIcon: Icon(Icons.search, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 32))),
      const SizedBox(height: 6),
      Expanded(child: Scrollbar(controller: _thoughtScroll, child: SingleChildScrollView(
        key: const ValueKey('project-thought-scroll'), controller: _thoughtScroll, primary: false,
        child: Wrap(spacing: 6, runSpacing: 6, children: [for (final r in thoughts)
          WordBadge(word: r.text, compact: true, dense: !_wide, onTap: () => showElementMetadata(context, r.text))])))),
    ]);
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_dirty, onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('변경 내용을 저장하지 않고 나갈까요?'), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 작성')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기'))]));
    if (discard == true && mounted) { setState(() => _dirty = false); WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) Navigator.pop(context); }); }
  }, child: Scaffold(appBar: AppBar(title: WorkspaceTitle(widget.project?.name ?? '프로젝트 만들기'), actions: [const KeyboardDismissAction(), const DesktopMenuAction(), IconButton(tooltip: _preview ? '편집' : '미리보기', icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _preview = !_preview)), TextButton(style: TextButton.styleFrom(minimumSize: Size(_wide ? 40 : 32, 40), padding: EdgeInsets.symmetric(horizontal: _wide ? 6 : 2), tapTargetSize: _wide ? MaterialTapTargetSize.padded : MaterialTapTargetSize.shrinkWrap), onPressed: _save, child: const Text('저장')),
    IconButton(tooltip: '작성 문법 안내', icon: const Icon(Icons.info_outline), onPressed: _showHelp),
  ]), body: DesktopMenuBody(child: SafeArea(top: false, child: LayoutBuilder(builder: (context, constraints) {
      final document = _preview
        ? SingleChildScrollView(child: DocumentMarkup(text: _body.text, links: _body.bindings))
        : CaretAssist(controller: _body, focus: _bodyFocus, useThoughtLabels: true,
          words: labelAssistTargets(excludeProject: widget.project), onWord: _insertLabel,
          tags: elements.tags.toList(), onTag: _insertTag,
          showWhenEmpty: false, enterSelectsVisible: true, showShortcutHint: true,
          child: TextField(key: const ValueKey('project-document'), controller: _body, focusNode: _bodyFocus, scrollController: _documentScroll, expands: true, minLines: null, maxLines: null,
          onTapOutside: _wide ? null : (_) {},
          onTap: () => _body.openAtCaret(context), textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: '본문을 작성하세요. 라벨 링크: [[표시명|라벨]]', border: OutlineInputBorder())));
      final panel = Material(key: const ValueKey('project-reference-panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(4), child: _referencesPanel()));
      return Column(children: [
        Expanded(child: Padding(padding: EdgeInsets.fromLTRB(_wide ? 12 : 6, 2, _wide ? 12 : 6, 0), child: !_thoughtPanelOpen ? document : _wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: document), const SizedBox(width: 12),
              SizedBox(width: (constraints.maxWidth * .45).clamp(300.0, 560.0), child: panel)])
          : Column(children: [Expanded(child: document), const SizedBox(height: 4), Expanded(child: panel)]))),
        TextButton.icon(key: const ValueKey('project-thought-panel-toggle'),
          style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 24), padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 10)),
          onPressed: () => setState(() => _thoughtPanelOpen = !_thoughtPanelOpen),
          icon: Icon(_thoughtPanelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 14),
          label: Text(_thoughtPanelOpen ? '생각 패널 숨기기' : '생각 패널 보이기')),
        TextButton.icon(key: const ValueKey('project-panel-toggle'),
          style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 24), padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 10)),
          onPressed: () => setState(() => _boxPanelOpen = !_boxPanelOpen),
          icon: Icon(_boxPanelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 14),
          label: Text(_boxPanelOpen ? '상자 패널 숨기기' : '상자 패널 보이기')),
        if (_boxPanelOpen) ThoughtFilters(key: const ValueKey('project-box-panel'),
          compact: !_wide, tags: elements.tags.toList()..sort(), selection: _filters,
          onFilter: _filters.toggle, onChanged: () { _refresh(); widget.onChanged?.call(); }),
      ]);
    })))));

  void _showHelp() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('프로젝트 작성 문법'),
    content: const SingleChildScrollView(child: Text(
      '제목 1: ======제목======\n제목 2: =====제목=====\n제목 3: ====제목====\n제목 4: ===제목===\n제목 5: ==제목==\n'
      '제목 안의 공백은 그대로 표시됩니다. 가장 먼저 나오는 제목을 프로젝트 이름으로 사용합니다.\n\n'
      '굵게: **텍스트**\n기울임: //텍스트//\n밑줄: __텍스트__\n취소선: --텍스트--\n\n'
      '왼쪽 정렬: |텍스트 |\n오른쪽 정렬: | 텍스트|\n가운데 정렬: | 텍스트 |\n\n'
      '링크: [[표시명|라벨 또는 프로젝트 제목]]\n웹 링크: [[표시명|https://example.com]]\n'
      '[[표시명|까지 입력하면 어시스트가 열립니다. Ctrl + Space로 선택할 수 있습니다. 프로젝트는 프로젝트: 접두어와 굵은 제목으로 표시됩니다.\n\n'
      '코드: <code>code</code>\n여러 줄도 가능하며 코드 안의 문법은 해석하지 않습니다.\n\n'
      '상단 미리보기 버튼으로 서식과 링크를 확인하세요.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  ));
}

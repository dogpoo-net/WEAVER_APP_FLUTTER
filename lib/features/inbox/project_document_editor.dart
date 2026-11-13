import 'document_table.dart';
import 'document_line_numbers.dart';
import 'edit_lock.dart';
import 'workspace_storage.dart';
import 'save_shortcuts.dart';
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
  const ProjectDocumentEditor({super.key, this.project, this.onChanged, this.onSave, this.onHistory, this.onLease, this.storage, this.onReload, this.projects = const []});
  final Future<Map<String,dynamic>> Function(String,String,bool)? onLease;
  final WorkspaceStorage? storage;
  final Future<void> Function()? onReload;
  final WritingProject? project;
  final List<WritingProject> projects;
  final Future<void> Function()? onChanged, onSave;
  final Future<void> Function(String)? onHistory;
  @override
  State<ProjectDocumentEditor> createState() => _ProjectDocumentEditorState();
}
class _ProjectDocumentEditorState extends State<ProjectDocumentEditor> {
  late final LabelTextController _body;
  bool _preview = false;
  EditLock? _lock;
  bool get _leaseGranted=>_lock?.granted??true;
  String? get _leaseMessage=>_lock?.message;
  bool get _needsLease=>widget.project!=null && (widget.onLease!=null || widget.storage?.documentLease!=null);
  Future<bool> _renewLease()async=>await _lock?.renew()??true;
  Future<void> _reload()async{
    if(widget.onReload==null || !await confirmReload(context))return;
    try{
      await widget.onReload!();await _renewLease();if(!mounted)return;
      _body.text=widget.project!.content;_body.bindings..clear()..addAll(widget.project!.documentLinks);
      _tags..clear()..addAll(widget.project!.tags);_filters.tags..clear()..addAll(_tags);setState(()=>_dirty=false);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('갱신하지 못했습니다. $e')));}
  }
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
    widget.storage?.editorResources.add(widget.project?.id??'new-document');
    if(_needsLease){_lock=EditLock(widget.project!.id,widget.storage,fallback:widget.onLease)..addListener(_refresh);}
    _body = LabelTextController( widget.project?.document ?? widget.project?.paragraphs.map((p) =>
      p.role == ParagraphRole.title ? '======${p.text}======' : p.role == ParagraphRole.subtitle ? '=====${p.text}=====' : p.text).join('\n\n') ?? '', widget.project?.documentLinks ?? const []);
    for (final project in widget.projects) { elements.indexProject(project); }
    if (widget.project != null) elements.indexProject(widget.project!);
    _tags.addAll(widget.project?.tags ?? {});
    if (widget.project?.document == null) _tags.addAll(widget.project?.paragraphs.expand((p) => p.tags) ?? <String>[]);
    _filters.tags.addAll(_tags); _filters.addListener(_refresh);
    _lastEdit = _editSignature;
    _body.addListener(_edited); elements.addListener(_refresh);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (visible && !_keyboardVisible) _boxPanelOpen = false;
    _keyboardVisible = visible;
  }
  String? _lastEdit;
  String get _editSignature => '${_body.text}|${_body.bindings.map((b) => '${b.id}:${b.start}:${b.end}').join(',')}';
  void _edited() {
    final edit = _editSignature;
    if (_lastEdit == edit) return;
    _lastEdit = edit;
    if (mounted) setState(() => _dirty = true);
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { widget.storage?.editorResources.remove(widget.project?.id??'new-document');_lock?.removeListener(_refresh);_lock?.dispose();elements.removeListener(_refresh); _body.dispose(); _bodyFocus.dispose(); _search.dispose(); _thoughtScroll.dispose(); _filters.dispose(); _documentScroll.dispose(); super.dispose(); }
  Future<void> _insertLabel(String word) async {
    await insertAssistedLink(context, _body, word); if (mounted) _bodyFocus.requestFocus();
  }
  void _insertTag(String tag) {
    final token = tagPrefix(_body.value);
    if (token.isEmpty) return;
    final end = _body.selection.end;
    _body.value = TextEditingValue(text: _body.text.replaceRange(end - token.length, end, '#$tag '),
      selection: TextSelection.collapsed(offset: end - token.length + tag.length + 2));
    _tags.add(tag); _bodyFocus.requestFocus();
  }
  Future<void> _insertTable() async {
    final before = _body.value;
    final table = await showDocumentTableDialog(context);
    if (!mounted || table == null || before.text != _body.text) return;
    final selection = before.selection;
    final start = selection.isValid ? selection.start : before.text.length;
    final end = selection.isValid ? selection.end : start;
    final text = '${start > 0 && before.text[start - 1] != '\n' ? '\n' : ''}$table\n';
    _body.value = TextEditingValue(text: before.text.replaceRange(start, end, text), selection: TextSelection.collapsed(offset: start + text.length));
    _bodyFocus.requestFocus();
  }
  bool _saving=false;
  Future<void> _save() async {
    if(_saving)return;
    _saving=true;
    try {
    if(_needsLease && !await _renewLease())return;
    if(!mounted)return;
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
    elements.indexProject(project); await widget.onChanged?.call(); await widget.onSave?.call();
    if (mounted) { setState(() => _dirty = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.storage?.lastSaveReplaced==true?'서버 최신 자료로 갱신했습니다.':'저장되었습니다.'))); }
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('저장 또는 동기화에 실패했습니다. 로컬 자료는 유지됩니다. $e'))); }
    finally {_saving=false;}
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
  Widget build(BuildContext context) => SaveShortcuts(onSave:_save,child:_build(context));
  Widget _build(BuildContext context) => PopScope(canPop: !_dirty, onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('변경 내용을 저장하지 않고 나갈까요?'), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 작성')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('나가기'))]));
    if (discard == true && mounted) { setState(() => _dirty = false); WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) Navigator.pop(context); }); }
  }, child: Scaffold(appBar: AppBar(title: WorkspaceTitle(widget.project?.name ?? '문서 만들기'), actions: [const KeyboardDismissAction(), const DesktopMenuAction(), if(_needsLease)IconButton(tooltip:_leaseMessage??'이 문서를 편집 중입니다',onPressed:()=>_leaseGranted?_renewLease():_lock?.takeOver(context),icon:Icon(_leaseGranted?Icons.lock_open:Icons.lock_outline)), if(widget.onReload!=null)IconButton(tooltip:'서버 자료 갱신',onPressed:_reload,icon:const Icon(Icons.refresh)), IconButton(tooltip: _preview ? '편집' : '미리보기', icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _preview = !_preview)), TextButton(style: TextButton.styleFrom(minimumSize: Size(_wide ? 40 : 32, 40), padding: EdgeInsets.symmetric(horizontal: _wide ? 6 : 2), tapTargetSize: _wide ? MaterialTapTargetSize.padded : MaterialTapTargetSize.shrinkWrap), onPressed: _leaseGranted?_save:null, child: const Text('저장')),
    if(widget.project!=null && widget.onHistory!=null)IconButton(tooltip:'문서 변경 이력',icon:const Icon(Icons.history),onPressed:()=>widget.onHistory!(widget.project!.id)),
    IconButton(tooltip: '작성 문법 안내', icon: const Icon(Icons.info_outline), onPressed: _showHelp),
   ]), bottomNavigationBar: _leaseGranted?null:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Text(_leaseMessage??'편집 권한을 확인하고 있습니다.'))), body: DesktopMenuBody(child: SafeArea(top: false, child: LayoutBuilder(builder: (context, constraints) {
      final document = !_leaseGranted
        ? SingleChildScrollView(child:SelectableText(_body.text))
        : _preview
        ? SingleChildScrollView(child: DocumentMarkup(text: _body.text, links: _body.bindings))
        : DocumentLineNumbers(controller: _body, scroll: _documentScroll, child: CaretAssist(controller: _body, focus: _bodyFocus, useThoughtLabels: true, selectionAssist: true,
          words: labelAssistTargets(excludeProject: widget.project), onWord: _insertLabel,
          tags: elements.tags.toList(), onTag: _insertTag,
          showWhenEmpty: false, enterSelectsVisible: true, showShortcutHint: true,
          child: TextField(key: const ValueKey('project-document'), controller: _body, focusNode: _bodyFocus, scrollController: _documentScroll, expands: true, minLines: null, maxLines: null,
          onTapOutside: _wide ? null : (_) {},
          onTap: () => _body.openAtCaret(context), textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: InputDecoration(fillColor: Theme.of(context).colorScheme.surfaceContainerHighest, hoverColor: Colors.transparent, focusColor: Colors.transparent, hintText: '본문을 작성하세요. 라벨 링크: [[표시명|라벨]]', border: const OutlineInputBorder()))));
      final panel = Material(key: const ValueKey('project-reference-panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(4), child: _referencesPanel()));
      return Column(children: [
        if (!_preview) Align(key: const ValueKey('document-editor-toolbar'), alignment: Alignment.centerLeft, child: TextButton.icon(style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12), tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _leaseGranted ? _insertTable : null, icon: const Icon(Icons.table_chart_outlined, size: 18), label: const Text('표 삽입'))),
        Expanded(child: Padding(padding: EdgeInsets.fromLTRB(_wide ? 12 : 6, 2, _wide ? 12 : 6, 0), child: _wide
          ? Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Expanded(child:document),if(_thoughtPanelOpen)...[const SizedBox(width:12),SizedBox(width:(constraints.maxWidth*.45).clamp(300.0,560.0),child:panel)],SizedBox(width:32,child:Align(alignment:Alignment.centerRight,child:IconButton(key:const ValueKey('project-thought-panel-toggle'),tooltip:_thoughtPanelOpen?'생각 패널 숨기기':'생각 패널 보이기',padding:EdgeInsets.zero,onPressed:()=>setState(()=>_thoughtPanelOpen=!_thoughtPanelOpen),icon:Icon(_thoughtPanelOpen?Icons.chevron_right:Icons.chevron_left))))])
          : !_thoughtPanelOpen?document:Column(children:[Expanded(child:document),const SizedBox(height:4),Expanded(child:panel)]))),
        if(!_wide)
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
    title: const Text('문서 작성 문법'),
    content: const SingleChildScrollView(child: Text(
      '제목 1: ======제목======\n제목 2: =====제목=====\n제목 3: ====제목====\n제목 4: ===제목===\n제목 5: ==제목==\n'
      '제목 안의 공백은 그대로 표시됩니다. 가장 먼저 나오는 제목을 문서 이름으로 사용합니다.\n\n'
      '굵게: **텍스트**\n기울임: //텍스트//\n밑줄: __텍스트__\n취소선: --텍스트--\n\n'
      '왼쪽 정렬: |텍스트 |\n오른쪽 정렬: | 텍스트|\n가운데 정렬: | 텍스트 |\n\n'
      '링크: [[표시명|라벨 또는 문서 제목]]\n웹 링크: [[표시명|https://example.com]]\n'
      '[[표시명|까지 입력하면 어시스트가 열립니다. Ctrl + Space로 선택할 수 있습니다. 문서는 문서: 접두어와 굵은 제목으로 표시됩니다.\n\n'
      '표: 상단 표 삽입 버튼에서 행·열과 내용을 입력하세요. 삽입 후 본문에서 수정하며 미리보기에서 표로 표시됩니다.\n| 제목 | 제목 |\n| --- | --- |\n| 내용 | 내용 |\n\n'
      '코드: <code>code</code>\n여러 줄도 가능하며 코드 안의 문법은 해석하지 않습니다.\n\n'
      '상단 미리보기 버튼으로 서식과 링크를 확인하세요.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  ));
}

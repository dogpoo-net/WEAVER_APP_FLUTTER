import 'package:flutter/gestures.dart';
import 'dart:async';
import 'dart:convert';
import '../sync/document_merge.dart';
import 'document_merge_dialog.dart';
import 'element_binding.dart';
import 'memo_boxes.dart';
import 'document_table.dart';
import 'document_line_numbers.dart';
import 'edit_lock.dart' show confirmReload;
import 'workspace_storage.dart';
import 'save_shortcuts.dart';
import 'thought_settings.dart';
import 'thought_filters.dart';
import 'label_links.dart';
import 'document_markup.dart';
import 'document_list_input.dart';
import 'document_diagnostics.dart';
import 'document_rich_editor.dart';
import 'document_syntax.dart' hide documentTitle;
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
  bool _preview = false, _loading = false, _rich = false;
  final _hoveredReference = ValueNotifier<String?>(null);
  final _syntaxTooltip = DocumentDiagnosticTooltip();
  Offset? _syntaxTouch;

  void _showSyntaxDiagnostic(String? message, Offset position, {bool touch = false}) {
    if (!mounted || message == null) {
      _syntaxTooltip.hide();
    } else {
      _syntaxTooltip.show(context, message, position, touch: touch);
    }
  }

  void _tapSource() {
    final position = _syntaxTouch;
    _syntaxTouch = null;
    if (position != null && _body.selection.isValid) {
      final offset = _body.selection.extentOffset;
      final issue = _body.syntaxDiagnostics.where((issue) =>
          issue.contains(offset) || issue.end == offset).firstOrNull;
      if (issue != null) {
        _showSyntaxDiagnostic(issue.message, position, touch: true);
        return;
      }
    }
    _syntaxTooltip.hide();
    _body.openAtCaret(context);
  }

  void _highlightReference(String? id) {
    if (mounted) _hoveredReference.value = id;
  }

  void _setRich(bool value) {
    _highlightReference(null);
    _syntaxTooltip.hide();
    FocusScope.of(context).unfocus();
    setState(() {
      _rich = value;
      _preview = false;
    });
  }

  void _applyRichPatch(int start, int end, String replacement) {
    final delta = replacement.length - (end - start);
    final text = _body.text.replaceRange(start, end, replacement);
    final links = [
      for (final link in _body.bindings)
        if (link.start >= end)
          ElementBinding(link.id, link.start + delta, link.end + delta)
        else
          link,
    ];
    _body.loadDocument(text, links,
      selection: TextSelection.collapsed(offset: start + replacement.length));
  }
  String get _draftId=>widget.project?.id??'new-document';
  Map<String,dynamic>? _original;
  bool get _canEdit=>widget.storage?.canvasWritable??true;
  bool _draftQueued=false;
  Future<void> _storeDraft()async{
    if(_loading || !_dirty || widget.storage==null)return;
    await widget.storage!.writeDocumentDraft(_draftId,{'text':_body.text,'links':_body.bindings.map((b)=>b.toJson()).toList(),'tags':{..._tags,..._filters.tags}.toList(),'base':_original});
  }
  void _queueDraft(){
    if(_draftQueued || _loading)return;_draftQueued=true;
    scheduleMicrotask(()async{_draftQueued=false;if(!mounted)return;try{await _storeDraft();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('로컬 초안을 저장하지 못했습니다. $e')));}});
  }
  Future<void> _reload()async{
    if(widget.onReload==null || !await confirmReload(context) || !mounted)return;
    if (_rich) _setRich(false);
    try{
      await widget.onReload!();if(!mounted)return;
      _loading=true;
      _body.text=widget.project!.content;_body.bindings..clear()..addAll(widget.project!.documentLinks);
      _tags..clear()..addAll(widget.project!.tags);_filters.tags..clear()..addAll(_tags);_captureBase();await widget.storage?.writeDocumentDraft(_draftId,null);setState(()=>_dirty=false);_loading=false;
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('갱신하지 못했습니다. $e')));}
  }
  final _search = TextEditingController(), _documentSearch = TextEditingController();
  final _dropEditorKey = GlobalKey();
  final _bodyFocus = FocusNode();
  final _tags = <String>{};
  final _filters = ThoughtFilterSelection();
  bool _dirty = false, _boxPanelOpen = false, _thoughtPanelOpen = true, _keyboardVisible = false;
  final _thoughtScroll = ScrollController(), _documentScroll = ScrollController(), _documentReferenceScroll = ScrollController();
  bool get _wide => MediaQuery.sizeOf(context).width >= 800;
  @override
  void initState() {
    super.initState();
    widget.storage?.editorResources.add(widget.project?.id??'new-document');
    _body = LabelTextController( widget.project?.document ?? widget.project?.paragraphs.map((p) =>
      p.role == ParagraphRole.title ? '======${p.text}======' : p.role == ParagraphRole.subtitle ? '=====${p.text}=====' : p.text).join('\n\n') ?? '', widget.project?.documentLinks ?? const []);
    for (final project in widget.projects) { elements.indexProject(project); }
    if (widget.project != null) elements.indexProject(widget.project!);
    _tags.addAll(widget.project?.tags ?? {});
    if (widget.project?.document == null) _tags.addAll(widget.project?.paragraphs.expand((p) => p.tags) ?? <String>[]);
    _filters.tags.addAll(_tags); _filters.addListener(_refresh);
    _captureBase();
    final draft=widget.storage?.documentDraft(_draftId);
    if(draft!=null){
      _body.loadDocument(draft['text'] as String,[for(final b in draft['links'] as List)ElementBinding(b['id'] as String,b['start'] as int,b['end'] as int)]);
      _tags..clear()..addAll(List<String>.from(draft['tags'] as List? ?? []));_filters.tags..clear()..addAll(_tags);
      _original=draft['base']==null?null:Map<String,dynamic>.from(draft['base'] as Map);widget.storage?.documentSaveBases[_draftId]=_original;_dirty=true;
    }
    _lastEdit = _editSignature;
    _body.editingDocument = true;
    _body.onSyntaxDiagnostic = _showSyntaxDiagnostic;
    _body.onLinkHover = _highlightReference;
    _body.addListener(_edited); elements.addListener(_refresh);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (visible && !_keyboardVisible) _boxPanelOpen = false;
    _keyboardVisible = visible;
  }
  void _captureBase(){
    final storage=widget.storage;if(storage==null||widget.project==null)return;
    final raw=storage.read();if(raw==null)return;
    final note=(jsonDecode(raw)['notes'] as List).where((n)=>n['project']?['id']==widget.project!.id).firstOrNull;
    if(note==null)return;
    final metadata=storage.itemMetadata?.call('list:notes',note['id'] as String);
    _original=metadata==null?null:jsonDecode(jsonEncode(metadata)) as Map<String,dynamic>;
    storage.documentSaveBases[_draftId]=_original;
  }
  String? _lastEdit;
  String get _editSignature => '${_body.text}|${_body.bindings.map((b) => '${b.id}:${b.start}:${b.end}').join(',')}';
  void _edited() {
    final edit = _editSignature;
    if (_lastEdit == edit) return;
    _lastEdit = edit;
    _syntaxTooltip.hide();
    if(_loading)return;
    if (mounted) setState(() => _dirty = true);
    _queueDraft();
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { widget.storage?.editorResources.remove(widget.project?.id??'new-document');elements.removeListener(_refresh); _body.dispose(); _syntaxTooltip.hide(); _hoveredReference.dispose(); _bodyFocus.dispose(); _search.dispose(); _documentSearch.dispose(); _documentReferenceScroll.dispose(); _thoughtScroll.dispose(); _filters.dispose(); _documentScroll.dispose(); super.dispose(); }
  Future<void> _insertLabel(String word) async {
    if (_rich) _setRich(false);
    await insertAssistedLink(context, _body, word);
    if (mounted) _bodyFocus.requestFocus();
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
  Future<void> _insertAnnotation({required bool footnote}) async {
    final before = _body.value;
    var draft = '';
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(footnote ? '각주 삽입' : '편집 주석 삽입'),
        content: TextField(
          autofocus: true,
          maxLines: 4,
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, draft.trim()), child: const Text('삽입')),
        ],
      ),
    );
    if (!mounted || !_canEdit || _saving || input == null || input.isEmpty || _body.text != before.text) return;
    final caret = before.selection.isValid ? before.selection.end : before.text.length;
    var offset = caret;
    for (final link in _body.bindings) {
      if (link.start < offset && offset < link.end) offset = link.end;
    }
    final text = input.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (footnote) {
      if (caretInsideCode(before.text, offset)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('코드 밖에 각주를 넣어주세요.')),
        );
        return;
      }
      final usedIds = documentFootnoteReference.allMatches(before.text).map((m) => m.group(1)).toSet();
      var next = 1;
      while (usedIds.contains('note-$next')) {
        next++;
      }
      final reference = '[^note-$next]';
      final definition = '\n\n$reference: $text';
      _body.value = TextEditingValue(
        text: before.text + definition,
        selection: TextSelection.collapsed(offset: offset),
      );
      _body.value = TextEditingValue(
        text: _body.text.replaceRange(offset, offset, reference),
        selection: TextSelection.collapsed(offset: offset + reference.length),
      );
    } else {
      final newline = before.text.indexOf('\n', offset);
      final end = newline < 0 ? before.text.length : newline;
      final comment = '\n<!-- $text -->';
      _body.value = TextEditingValue(
        text: before.text.replaceRange(end, end, comment),
        selection: TextSelection.collapsed(offset: end + comment.length),
      );
    }
    _bodyFocus.requestFocus();
  }

  bool _saving=false;
  Future<void> _save() async {
    if(_saving)return;
    final issue = _body.syntaxDiagnostics.firstOrNull;
    if (issue != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(issue.message)));
      return;
    }
    if (_rich) _setRich(false);
    setState(()=>_saving=true);
    try {
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
    await _storeDraft();
    if(!mounted)return;
    if (widget.project == null) { setState((){_dirty=false;_saving=false;});Navigator.pop(context, project); return; }
    elements.indexProject(project); await widget.onChanged?.call(); await widget.onSave?.call();
    final storage=widget.storage;
    if(storage?.syncResource!=null){
      final saved=WorkspaceSnapshot.decode(storage!.read()!).notes.where((n)=>n.project?.id==project.id).firstOrNull?.project;
      if(saved!=null){project.document=saved.document;project.documentLinks=saved.documentLinks;project.name=saved.name;project.tags..clear()..addAll(saved.tags);_tags..clear()..addAll(saved.tags);_filters.tags..clear()..addAll(saved.tags);_loading=true;_body.loadDocument(project.content,project.documentLinks);_loading=false;}
      _original=storage.documentSaveBases[project.id];
    }
    await storage?.writeDocumentDraft(_draftId,null);
    if (mounted) { setState(() => _dirty = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.storage?.lastSaveReplaced==true?'서버 최신 자료로 갱신했습니다.':'저장되었습니다.'))); }
    } on DocumentMergeConflict catch(conflict){
      if(!mounted)return;
      final resolved=await resolveDocumentConflict(context,conflict);
      if(resolved!=null&&mounted){
        final content=documentSegment(resolved);_loading=true;_body.loadDocument(content.text,content.links);_loading=false;
        _tags..clear()..addAll(List<String>.from(resolved['project']['tags'] as List? ?? []));_filters.tags..clear()..addAll(_tags);
        _original=conflict.remoteItem;widget.storage?.documentSaveBases[_draftId]=_original;
        _dirty=true;await _storeDraft();_saving=false;await _save();
      }
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('저장 또는 동기화에 실패했습니다. 로컬 자료는 유지됩니다. $e'))); }
    finally {if(mounted){setState(()=>_saving=false);}else{_saving=false;}}
  }
  Widget _referenceBadge(String key) {
    final project = projectTarget(key);
    final targetId = project != null ? key : 'label:${elements.records[key]?.id}';
    final badge = ValueListenableBuilder<String?>(
      valueListenable: _hoveredReference,
      builder: (context, hovered, _) => WordBadge(
        word: key, displayText: project != null || !_wide ? assistTargetTitle(key) : null,
        project: project != null, labelTarget: !_wide && isLabelAssistTarget(key),
        memo: !_wide && project == null && !isLabelAssistTarget(key), compact: true, dense: !_wide,
        selected: hovered == targetId,
        onTap: () => project != null ? openInlineLink(context, key) : showElementMetadata(context, key),
      ),
    );
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: 180, child: WordBadge(word: key,
      displayText: assistTargetTitle(key), project: project != null, compact: true, onTap: () {})));
    return _wide ? Draggable<InlineLinkDrag>(dragAnchorStrategy: pointerDragAnchorStrategy, data: InlineLinkDrag(key), feedback: feedback, childWhenDragging: Opacity(opacity: .4, child: badge), child: badge)
      : LongPressDraggable<InlineLinkDrag>(dragAnchorStrategy: pointerDragAnchorStrategy, data: InlineLinkDrag(key), feedback: feedback, childWhenDragging: Opacity(opacity: .4, child: badge), child: badge);
  }
  Widget _referenceList({required bool documents}) {
    final controller = documents ? _documentSearch : _search;
    final query = controller.text.trim().replaceFirst('#', '').toLowerCase();
    final targets = <String>[for (final project in indexedProjects) if (project != widget.project) 'project:${project.id}',
      ...elements.records.keys.where(isLabelAssistTarget), ...elements.records.keys.where((key) => !isLabelAssistTarget(key))].where((key) {
      final project = projectTarget(key);
      if (_wide && documents != (project != null)) return false;
      if (project != null) return assistTargetMatches(key, query);
      final record = elements.records[key];
      return record != null && canBrowseThought(record) && _filters.matches(record) &&
        (assistTargetMatches(key, query) || record.tags.any((tag) => tag.contains(query)));
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(key: ValueKey(documents ? 'project-document-reference-search' : 'project-reference-search'), controller: controller,
        onTapOutside: _wide ? null : (_) {}, style: const TextStyle(fontSize: 12), onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: documents ? '문서 제목·내용 찾기' : _wide ? '생각·해시태그 찾기' : '문서·라벨·메모 찾기', isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 32))),
      const SizedBox(height: 6),
      Expanded(child: Scrollbar(controller: documents ? _documentReferenceScroll : _thoughtScroll, child: SingleChildScrollView(
        key: ValueKey(documents ? 'project-document-reference-scroll' : 'project-thought-scroll'),
        controller: documents ? _documentReferenceScroll : _thoughtScroll, primary: false,
        child: Wrap(spacing: 6, runSpacing: 6, children: targets.map(_referenceBadge).toList())))),
    ]);
  }
  double _referenceSplit=.5;
  double _referenceDragY=0,_referenceDragHeight=0;
  Widget _referencesPanel() => !_wide ? _referenceList(documents: false) : LayoutBuilder(builder:(context,constraints){
    final available=(constraints.maxHeight-16).clamp(0.0,double.infinity);
    final minimum=available>0?(56/available).clamp(.15,.5):.5;
    final split=_referenceSplit.clamp(minimum,1-minimum);
    return Column(children:[
      SizedBox(height:available*split,child:_referenceList(documents:false)),
      MouseRegion(cursor:SystemMouseCursors.resizeUpDown,child:GestureDetector(
        key:const ValueKey('document-reference-divider'),behavior:HitTestBehavior.opaque,
        dragStartBehavior:DragStartBehavior.down,
        onVerticalDragStart:(details){_referenceDragY=details.globalPosition.dy;_referenceDragHeight=available*split;},
        onVerticalDragUpdate:(details){if(available>0)setState(()=>_referenceSplit=((_referenceDragHeight+details.globalPosition.dy-_referenceDragY)/available).clamp(minimum,1-minimum));},
        child:Tooltip(message:'드래그하여 패널 높이 조절',child:SizedBox(height:16,child:Center(child:Container(width:40,height:3,decoration:BoxDecoration(color:Theme.of(context).colorScheme.outlineVariant,borderRadius:BorderRadius.circular(2)))))))),
      Expanded(child:_referenceList(documents:true)),
    ]);
  });
  String? _dragKey(Object data) {
    if (data is InlineLinkDragSource) return data.linkKey;
    if (data is MemoDrag) return elements.byId(data.id)?.text;
    return null;
  }
  Future<void> _dropLink(DragTargetDetails<Object> details) async {
    final key = _dragKey(details.data); if (key == null || !_canEdit || _saving) return;
    EditableTextState? editor;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) { editor = element.state as EditableTextState; return; }
      element.visitChildren(visit);
    }
    final anchor = _dropEditorKey.currentContext; if (anchor == null) return;
    visit(anchor as Element);
    var offset = editor?.renderEditable.getPositionForPoint(details.offset).offset ?? _body.text.length;
    for (final link in _body.bindings) { if (link.start < offset && offset < link.end) offset = link.end; }
    _body.selection = TextSelection.collapsed(offset: offset.clamp(0, _body.text.length));
    await insertAssistedLink(context, _body, key, alwaysPrompt: true, replaceQuery: false);
    if (mounted) _bodyFocus.requestFocus();
  }
  Future<void> _showBoxFilters() async {
    _bodyFocus.unfocus();
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: ListenableBuilder(
      listenable: _filters, builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [const SizedBox(width: 16), const Expanded(child: Text('메모상자·태그')), IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
        ThoughtFilters(key: const ValueKey('project-box-panel'), tags: elements.tags.toList()..sort(), selection: _filters,
          onFilter: _filters.toggle, onChanged: () { _refresh(); widget.onChanged?.call(); }), const SizedBox(height: 12),
      ]))));
  }
  @override
  Widget build(BuildContext context) => SaveShortcuts(onSave:_save,child:_build(context));
  Widget _build(BuildContext context) => PopScope(canPop: !_saving && !_dirty, onPopInvokedWithResult: (didPop, result) async {
    if(didPop || _saving)return;
    try{await _storeDraft();if(mounted){setState(()=>_dirty=false);WidgetsBinding.instance.addPostFrameCallback((_){if(context.mounted)Navigator.pop(context);});}}
    catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('초안을 보관하지 못했습니다. $e')));}
  }, child: Scaffold(appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: const WorkspaceTitle('문서 작성'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(36, 40), maximumSize: const Size(36, 40), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const KeyboardDismissAction(), const DesktopMenuAction(), if(widget.onReload!=null)IconButton(tooltip:'서버 자료 갱신',onPressed:_reload,icon:const Icon(Icons.refresh)), IconButton(tooltip: _preview ? '편집' : '미리보기', icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined), onPressed: () { _highlightReference(null); _syntaxTooltip.hide(); setState(() => _preview = !_preview); }), IconButton(tooltip: '저장', icon: const Icon(Icons.save_outlined), onPressed: _canEdit && !_saving ? _save : null),
    IconButton(tooltip: '작성 문법 안내', icon: const Icon(Icons.info_outline), onPressed: _showHelp),
   ]))]), bottomNavigationBar: _canEdit?null:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Text('읽기 전용 워크스페이스입니다.'))), body: DesktopMenuBody(child: SafeArea(top: false, child: LayoutBuilder(builder: (context, constraints) {
      final modeSwitch = TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _saving ? null : () => _setRich(!_rich),
        icon: Icon(_rich ? Icons.code : Icons.format_paint_outlined, size: 18),
        label: Text(_rich ? '원문 편집' : '서식 편집'),
      );
      final documentBody = !_canEdit
        ? SingleChildScrollView(child:SelectableText(_body.text))
        : _preview
        ? SingleChildScrollView(child: DocumentMarkup(text: _body.text, links: _body.bindings))
        : _rich
        ? DocumentRichEditor(source: _body.text, links: _body.bindings, onPatch: _applyRichPatch, onLinkHover: _highlightReference, modeSwitch: modeSwitch, dirty: _dirty, diagnostics: _body.syntaxDiagnostics, onSyntaxDiagnostic: _showSyntaxDiagnostic)
        : DocumentLineNumbers(controller: _body, scroll: _documentScroll, child: CaretAssist(controller: _body, focus: _bodyFocus, useThoughtLabels: true, selectionAssist: true,
          words: labelAssistTargets(excludeProject: widget.project), onWord: _insertLabel,
          tags: elements.tags.toList(), onTag: _insertTag,
          showWhenEmpty: false, enterSelectsVisible: true, showShortcutHint: true,
          child: Stack(fit:StackFit.expand,children:[Listener(
          onPointerDown: (event) {
            _syntaxTouch = event.kind == PointerDeviceKind.touch ? event.position : null;
            _syntaxTooltip.hide();
          },
          child: TextField(key: const ValueKey('project-document'), readOnly: _saving, controller: _body, focusNode: _bodyFocus, scrollController: _documentScroll, expands: true, minLines: null, maxLines: null,
          onTapOutside: _wide ? null : (_) {},
          inputFormatters: const [DocumentListInput()],
          onTap: _tapSource, textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: InputDecoration(contentPadding:EdgeInsets.fromLTRB(12,16,12,_dirty?36:16),fillColor: Theme.of(context).colorScheme.surfaceContainerHighest, hoverColor: Colors.transparent, focusColor: Colors.transparent, hintText: '본문을 작성하세요. 라벨 링크: [[표시명|라벨]]', border: const OutlineInputBorder()))),
          if(_dirty)const Positioned(left:12,right:12,bottom:8,child:IgnorePointer(child:Text('아직 저장되지 않았습니다.',textAlign:TextAlign.center,style:TextStyle(color:Colors.red,fontSize:12)))),
        ])));
      final documentInput = !_canEdit || _preview || _rich ? documentBody : DragTarget<Object>(key: const ValueKey('document-link-drop'),
        onWillAcceptWithDetails: (details) => !_saving && _dragKey(details.data) != null,
        onAcceptWithDetails: _dropLink, builder: (context, candidates, rejected) => KeyedSubtree(key: _dropEditorKey, child: documentBody));
      final panel = Material(key: const ValueKey('project-reference-panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(4), child: _referencesPanel()));
      final document = Column(children: [
        if (!_preview && !_rich && _canEdit) DocumentEditorToolbar(
          key: const ValueKey('document-editor-toolbar'),
          modeSwitch: modeSwitch,
          tools: [
            IconButton(
              tooltip: '편집 주석 삽입',
              onPressed: _saving ? null : () => _insertAnnotation(footnote: false),
              icon: const Icon(Icons.comment_outlined),
            ),
            IconButton(
              tooltip: '각주 삽입',
              onPressed: _saving ? null : () => _insertAnnotation(footnote: true),
              icon: const Icon(Icons.format_list_numbered),
            ),
            IconButton(
              tooltip: '표 삽입',
              onPressed: _saving ? null : _insertTable,
              icon: const Icon(Icons.table_chart_outlined),
            ),
          ],
        ),
        Expanded(child: documentInput),
      ]);
      return Column(children: [
        Expanded(child: Padding(padding: EdgeInsets.fromLTRB(_wide ? 12 : 6, 2, _wide ? 12 : 6, 0), child: _wide
          ? Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Expanded(child:document),if(_thoughtPanelOpen)...[const SizedBox(width:12),SizedBox(width:(constraints.maxWidth*.45).clamp(300.0,560.0),child:panel)],SizedBox(width:32,child:Align(alignment:Alignment.centerRight,child:IconButton(key:const ValueKey('project-thought-panel-toggle'),tooltip:_thoughtPanelOpen?'생각 패널 숨기기':'생각 패널 보이기',padding:EdgeInsets.zero,onPressed:()=>setState(()=>_thoughtPanelOpen=!_thoughtPanelOpen),icon:Icon(_thoughtPanelOpen?Icons.chevron_right:Icons.chevron_left))))])
          : !_thoughtPanelOpen?document:Column(children:[Expanded(flex:7,child:document),const SizedBox(height:4),Expanded(flex:3,child:panel)]))),
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
          onPressed: _wide ? () => setState(() => _boxPanelOpen = !_boxPanelOpen) : _showBoxFilters,
          icon: Icon(_wide ? (_boxPanelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up) : Icons.inventory_2_outlined, size: 14),
          label: Text(!_wide ? '메모상자·태그' : _boxPanelOpen ? '상자 패널 숨기기' : '상자 패널 보이기')),
        if (_wide && _boxPanelOpen) ThoughtFilters(key: const ValueKey('project-box-panel'),
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
      '코드: <code>code</code>\n언어 표시: <code lang="python">code</code>\n여러 줄도 가능하며 코드 안의 문법은 해석하지 않습니다.\n\n'
      '상단 미리보기 버튼으로 서식과 링크를 확인하세요.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  ));
}

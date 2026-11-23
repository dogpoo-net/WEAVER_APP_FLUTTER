import 'package:flutter/gestures.dart';
import 'dart:async';
import 'dart:convert';
import '../sync/document_merge.dart';
import 'document_merge_dialog.dart';
import 'element_binding.dart';
import 'memo_boxes.dart';
import 'document_table.dart';
import 'document_ai_panel.dart';
import 'document_line_numbers.dart';
import 'document_footnote_dialog.dart';
import 'document_line_shortcuts.dart';
import 'workspace_photo_actions.dart';
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
      _richLineSelection = null;
      _richAiCaret = null;
      _rich = value;
      _preview = false;
    });
  }

  void _applyRichPatch(int start, int end, String replacement, {TextSelection? selection, List<DocumentLineSlice>? slices}) {
    final source = _body.text;
    final delta = replacement.length - (end - start);
    final links = <ElementBinding>[];
    final used = <int>{};
    for (final link in _body.bindings) {
      if (link.end <= start) {
        links.add(link);
      } else if (link.start >= end) {
        links.add(ElementBinding(link.id, link.start + delta, link.end + delta));
      } else if (slices != null) {
        for (final slice in slices) {
          if (link.start < slice.start || link.end > slice.end) continue;
          final shift = slice.destination - slice.start;
          links.add(ElementBinding(link.id, link.start + shift, link.end + shift));
        }
      } else if (link.start >= start && link.end <= end) {
        final label = source.substring(link.start, link.end);
        var position = replacement.indexOf(label);
        while (position >= 0 && used.contains(position)) {
          position = replacement.indexOf(label, position + label.length);
        }
        if (position >= 0) {
          used.add(position);
          links.add(ElementBinding(link.id, start + position, start + position + label.length));
        }
      }
    }
    links.sort((a, b) => a.start.compareTo(b.start));
    _body.loadDocument(source.replaceRange(start, end, replacement), links,
      selection: selection ?? TextSelection.collapsed(offset: start + replacement.length));
  }

  void _editLines(DocumentLineAction action, TextSelection selection) {
    if (_saving || !_canEdit) return;
    final edit = editDocumentLines(_body.text, selection, action);
    if (edit == null) return;
    _applyRichPatch(edit.start, edit.end, edit.replacement, selection: edit.selection, slices: edit.slices);
    if (_rich) setState(() {
      _richLineSelection = edit.selection;
      _richInsertionRevision++;
    });
  }

  Future<void> _insertPhoto(int offset) async {
    final before = _body.text;
    final photo = await chooseWorkspacePhoto(context, widget.storage);
    if (!mounted || !_canEdit || _saving || photo == null || before != _body.text) return;
    _insertVisualBlock(offset, '<photo id="${photo.id}">');
  }

  void _insertVisualBlock(int offset, String block) {
    if (!_canEdit || _saving) return;
    final source = _body.text;
    final newline = source.indexOf('\n', offset);
    final end = newline < 0 ? source.length : newline;
    final prefix = end > 0 && source[end - 1] != '\n' ? '\n' : '';
    final suffix = newline < 0 || prefix.isEmpty ? '\n' : '';
    _applyRichPatch(end, end, '$prefix$block$suffix');
    _finishInsertion();
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
    if(_draftQueued || _loading || _saving)return;_draftQueued=true;
    scheduleMicrotask(()async{_draftQueued=false;if(!mounted || _saving)return;try{await _storeDraft();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('로컬 초안을 저장하지 못했습니다. $e')));}});
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
  final _search = TextEditingController();
  final _dropEditorKey = GlobalKey();
  final _bodyFocus = FocusNode();
  final _tags = <String>{};
  final _filters = ThoughtFilterSelection();
  bool _confirmingExit = false;
  bool _previousThoughtPanel = true, _previousBoxPanel = false;
  String _previewRevision = '';
  void _togglePreview() {
    setState(() {
      _preview = !_preview;
      if (_preview) {
        _previousThoughtPanel = _thoughtPanelOpen;
        _previousBoxPanel = _boxPanelOpen;
        _thoughtPanelOpen = _boxPanelOpen = false;
      } else {
        _thoughtPanelOpen = _previousThoughtPanel;
        _boxPanelOpen = _previousBoxPanel;
      }
    });
    final project = widget.project;
    if (_preview && project != null) {
      documentRevisionLabel(widget.storage, project.id).then((label) {
        if (mounted && _preview) setState(() => _previewRevision = label);
      });
    }
  }
  bool _dirty = false, _boxPanelOpen = false, _thoughtPanelOpen = true, _keyboardVisible = false;
  final _thoughtScroll = ScrollController(), _documentScroll = ScrollController();
  bool get _wide => MediaQuery.sizeOf(context).width >= 800;
  @override
  void initState() {
    super.initState();
    leaveDocumentEditor = _confirmExit;
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
  void dispose() { if (leaveDocumentEditor == _confirmExit) leaveDocumentEditor = null; widget.storage?.editorResources.remove(widget.project?.id??'new-document');elements.removeListener(_refresh); _body.dispose(); _syntaxTooltip.hide(); _hoveredReference.dispose(); _bodyFocus.dispose(); _search.dispose(); _thoughtScroll.dispose(); _filters.dispose(); _documentScroll.dispose(); super.dispose(); }
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
  int _richInsertionRevision = 0;
  TextSelection? _richLineSelection;

  Future<void> _insertTable({int? richOffset}) async {
    final before = _body.value;
    final table = await showDocumentTableDialog(context);
    if (!mounted || !_canEdit || _saving || table == null || before.text != _body.text) return;
    final selection = before.selection;
    final lineEnd = richOffset == null ? -1 : before.text.indexOf('\n', richOffset);
    final start = richOffset == null
        ? (selection.isValid ? selection.start : before.text.length)
        : (lineEnd < 0 ? before.text.length : lineEnd);
    final end = richOffset == null && selection.isValid ? selection.end : start;
    final text = '${start > 0 && before.text[start - 1] != '\n' ? '\n' : ''}$table\n';
    _body.value = TextEditingValue(text: before.text.replaceRange(start, end, text), selection: TextSelection.collapsed(offset: start + text.length));
    _finishInsertion();
  }

  Future<void> _insertFootnote(int caret) async {
    final before = _body.value;
    var offset = caret;
    for (final link in _body.bindings) {
      if (link.start < offset && offset < link.end) offset = link.end;
    }
    final comments = DocumentComments(before.text);
    final codeRanges = codeMarkup.allMatches(comments.maskedText).toList();
    final notes = <String, String>{};
    var start = 0;
    for (final line in before.text.split('\n')) {
      final definition = documentFootnoteDefinition.firstMatch(line);
      if (definition != null &&
          !comments.ranges.any((range) => range.start <= start && range.end > start) &&
          !codeRanges.any((range) => range.start <= start && range.end > start)) {
        notes.putIfAbsent(definition.group(1)!, () => definition.group(2)!);
      }
      start += line.length + 1;
    }
    for (final reference in documentFootnoteReference.allMatches(before.text)) {
      if (reference.start < offset && offset < reference.end) offset = reference.end;
    }
    final usedIds = documentFootnoteReference.allMatches(before.text)
        .map((match) => match.group(1)!).toSet();
    var changed = false;
    final selected = await showDocumentFootnotes(
      context,
      notes: notes,
      onAdd: (text) {
        var next = 1;
        while (usedIds.contains('note-$next')) { next++; }
        final id = 'note-$next';
        usedIds.add(id);
        final source = _body.text;
        _applyRichPatch(source.length, source.length,
          '\n\n[^$id]: $text',
          selection: before.selection);
        changed = true;
        return id;
      },
    );
    if (!mounted) return;
    if (_canEdit && !_saving && selected != null) {
      if (caretInsideCode(comments.maskedText, offset) ||
          comments.ranges.any((range) => range.start < offset && offset < range.end)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('코드나 주석 밖에 각주를 넣어주세요.')),
        );
      } else {
        final reference = '[^$selected]';
        _applyRichPatch(offset, offset, reference,
          selection: TextSelection.collapsed(offset: offset + reference.length));
        changed = true;
      }
    }
    if (changed) _finishInsertion(selection: _body.selection);
  }

  void _finishInsertion({TextSelection? selection}) {
    if (_rich) {
      setState(() {
        _richLineSelection = selection;
        _richInsertionRevision++;
      });
    } else {
      _bodyFocus.requestFocus();
    }
  }

  void _refreshRichAfterSaveChange(String previous) {
    if (_rich && previous != _body.text) {
      setState(() {
        _richLineSelection = null;
        _richInsertionRevision++;
      });
    }
  }

  bool _saving=false;
  Future<void> _save() async {
    if(_saving)return;
    final issue = _body.syntaxDiagnostics.firstOrNull;
    if (issue != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(issue.message)));
      return;
    }
    setState(()=>_saving=true);
    try {
    if(!mounted)return;
    final beforeLinkCompletion = _body.text;
    _body.completeLinks();
    _refreshRichAfterSaveChange(beforeLinkCompletion);
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
    // Both editor modes patch _body. The edit session owns the compare base
    // until this save is acknowledged or the user resolves a real conflict.
    widget.storage?.documentSaveBases[project.id] = _original;
    elements.indexProject(project); await widget.onChanged?.call(); await widget.onSave?.call();
    final storage=widget.storage;
    if(storage?.syncResource!=null){
      final saved=WorkspaceSnapshot.decode(storage!.read()!).notes.where((n)=>n.project?.id==project.id).firstOrNull?.project;
      if(saved!=null){project.document=saved.document;project.documentLinks=saved.documentLinks;project.name=saved.name;project.tags..clear()..addAll(saved.tags);_tags..clear()..addAll(saved.tags);_filters.tags..clear()..addAll(saved.tags);final previous = _body.value;_loading=true;_body.loadDocument(project.content,project.documentLinks, selection: previous.text == project.content ? previous.selection : null);_loading=false;_refreshRichAfterSaveChange(previous.text);}
      _original=storage.documentSaveBases[project.id];
    }
    await storage?.writeDocumentDraft(_draftId,null);
    if (mounted) { setState(() => _dirty = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.storage?.lastSaveReplaced==true?'서버 최신 자료로 갱신했습니다.':'저장되었습니다.'))); }
    } on DocumentMergeConflict catch(conflict){
      if(!mounted)return;
      final resolved=await resolveDocumentConflict(context,conflict);
      if(resolved!=null&&mounted){
        final content=documentSegment(resolved);final previous=_body.text;_loading=true;_body.loadDocument(content.text,content.links);_loading=false;_refreshRichAfterSaveChange(previous);
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
        word: key, displayText: assistTargetTitle(key),
        project: project != null, labelTarget: isLabelAssistTarget(key),
        memo: project == null && !isLabelAssistTarget(key), compact: true, dense: !_wide,
        selected: hovered == targetId,
        onTap: () => project != null ? openInlineLink(context, key) : showElementMetadata(context, key),
      ),
    );
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: 180, child: WordBadge(word: key,
      displayText: assistTargetTitle(key), project: project != null, compact: true, onTap: () {})));
    return _wide ? Draggable<InlineLinkDrag>(dragAnchorStrategy: pointerDragAnchorStrategy, data: InlineLinkDrag(key), feedback: feedback, childWhenDragging: Opacity(opacity: .4, child: badge), child: badge)
      : LongPressDraggable<InlineLinkDrag>(dragAnchorStrategy: pointerDragAnchorStrategy, data: InlineLinkDrag(key), feedback: feedback, childWhenDragging: Opacity(opacity: .4, child: badge), child: badge);
  }
  Widget _referenceList() {
    final query = _search.text.trim().replaceFirst('#', '').toLowerCase();
    final targets = <String>[for (final project in indexedProjects) if (project != widget.project) 'project:${project.id}',
      ...elements.records.keys.where(isLabelAssistTarget), ...elements.records.keys.where((key) => !isLabelAssistTarget(key))].where((key) {
      final project = projectTarget(key);
      if (project != null) return assistTargetMatches(key, query);
      final record = elements.records[key];
      return record != null && canBrowseThought(record) && _filters.matches(record) &&
        (assistTargetMatches(key, query) || record.tags.any((tag) => tag.contains(query)));
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(key: const ValueKey('project-reference-search'), controller: _search,
        onTapOutside: _wide ? null : (_) {}, style: const TextStyle(fontSize: 12), onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: '문서, 생각, 라벨, 해시태그 찾기', isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 32))),
      const SizedBox(height: 6),
      Expanded(child: Scrollbar(controller: _thoughtScroll, child: SingleChildScrollView(
        key: const ValueKey('project-thought-scroll'),
        controller: _thoughtScroll, primary: false,
        child: Wrap(spacing: 6, runSpacing: 6, children: targets.map(_referenceBadge).toList())))),
    ]);
  }
  int? _richAiCaret;
  bool _showDesktopAi = true;
  double _desktopReferenceEnd = .58;
  double _desktopDragY = 0, _desktopDragOffset = 0;

  DocumentAiThought? _aiThought(String key) {
    if (projectTarget(key) != null) return null;
    final thought = labelTarget(key) ?? elements.records[key];
    if (thought == null || !canBrowseThought(thought)) return null;
    return (id: thought.id, title: thought.title, text: thought.text, tags: thought.tags);
  }

  bool _insertAiResult(String text) {
    if (!mounted || !_canEdit || _saving) return false;
    final caret = _rich ? _richAiCaret : _body.selection.extentOffset;
    final offset = (caret == null || caret < 0 ? _body.text.length : caret)
        .clamp(0, _body.text.length);
    _insertVisualBlock(offset, text);
    return true;
  }

  Widget _aiPanel(DocumentAiRequest request, {required bool desktop}) =>
      DocumentAiPanel(
        thoughts: desktop ? const [] : [
          for (final key in elements.records.keys)
            if (_aiThought(key) case final thought?) thought,
        ],
        thoughtForDrag: desktop ? (drag) => _aiThought(drag.linkKey) : null,
        request: request,
        onInsert: _insertAiResult,
      );

  void _openAi() {
    final request = widget.storage?.documentAiRequest;
    if (request == null || !_canEdit || _saving) return;
    FocusScope.of(context).unfocus();
    if (_wide) {
      setState(() {
        _showDesktopAi = !_thoughtPanelOpen || !_showDesktopAi;
        _thoughtPanelOpen = true;
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) => SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: FractionallySizedBox(
            heightFactor: .99,
            child: _aiPanel(request, desktop: false),
          ),
        ),
      ),
    );
  }

  Widget _desktopDivider({
    required String key,
    required double position,
    required ValueChanged<double> onMove,
  }) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (details) {
        _desktopDragY = details.globalPosition.dy;
        _desktopDragOffset = position;
      },
      onVerticalDragUpdate: (details) =>
          onMove(_desktopDragOffset + details.globalPosition.dy - _desktopDragY),
      child: Tooltip(
        message: '드래그하여 패널 높이 조절',
        child: SizedBox(
          height: 16,
          width: double.infinity,
          child: Center(child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
      ),
    ),
  );

  Widget _desktopPane(double height, Widget child, {double minimum = 48}) {
    final layoutHeight = height < minimum ? minimum : height;
    return SizedBox(
      height: height,
      child: Offstage(
        offstage: height == 0,
        child: ClipRect(child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: layoutHeight,
          maxHeight: layoutHeight,
          child: child,
        )),
      ),
    );
  }

  Widget _desktopReferencePanels() {
    final request = widget.storage?.documentAiRequest;
    if (!_showDesktopAi || request == null || !_canEdit) return _referenceList();
    return LayoutBuilder(builder: (context, constraints) {
      final available = (constraints.maxHeight - 16).clamp(0.0, double.infinity);
      if (available == 0) return const SizedBox.shrink();
      final split = available * _desktopReferenceEnd;
      return Column(children: [
        _desktopPane(split, _referenceList()),
        _desktopDivider(
          key: 'document-ai-divider',
          position: split,
          onMove: (position) => setState(() => _desktopReferenceEnd =
              (position / available).clamp(0.0, 1.0)),
        ),
        _desktopPane(available - split, _aiPanel(request, desktop: true), minimum: 220),
      ]);
    });
  }

  double _mobilePanelFraction = .3;
  double _mobileDragStart = 0, _mobileDragHeight = 0;

  Widget _mobileDocumentSplit(Widget document, Widget panel) =>
      LayoutBuilder(builder: (context, constraints) {
        final handleHeight = constraints.maxHeight.clamp(0.0, 24.0);
        final available = constraints.maxHeight - handleHeight;
        final maxPanel = (available - 100).clamp(0.0, available * .7);
        final desiredHeight = (_mobilePanelFraction * available).clamp(0.0, maxPanel);
        final panelHeight = _thoughtPanelOpen && desiredHeight >= 48 ? desiredHeight : 0.0;
        return Column(children: [
          Expanded(child: document),
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              key: const ValueKey('mobile-document-divider'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: (details) {
                _mobileDragStart = details.globalPosition.dy;
                _mobileDragHeight = panelHeight;
              },
              onVerticalDragUpdate: (details) {
                if (available <= 0) return;
                final height = (_mobileDragHeight + _mobileDragStart -
                    details.globalPosition.dy).clamp(0.0, maxPanel);
                setState(() {
                  _thoughtPanelOpen = true;
                  _mobilePanelFraction = height / available;
                });
              },
              child: SizedBox(
                height: handleHeight,
                width: double.infinity,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const ValueKey('project-thought-panel-toggle'),
                      tooltip: panelHeight > 0 ? '생각 패널 숨기기' : '생각 패널 보이기',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 24),
                      iconSize: 16,
                      onPressed: () => setState(() {
                        _thoughtPanelOpen = panelHeight == 0;
                        if (_thoughtPanelOpen && desiredHeight < 48) _mobilePanelFraction = .3;
                      }),
                      icon: Icon(panelHeight > 0 ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          if (panelHeight > 0) SizedBox(height: panelHeight, child: panel),
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
  Future<bool> _confirmExit() async {
    if (ModalRoute.of(context)?.isCurrent != true) return true;
    if (_saving || _confirmingExit) return false;
    _confirmingExit = true;
    try {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(_dirty ? '저장하지 않은 자료가 있습니다. 정말 나갈까요?' : '문서 작성을 마치고 나갈까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('나가기')),
          ],
        ),
      );
      if (leave != true || !mounted) return false;
      await widget.storage?.writeDocumentDraft(_draftId, null);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
      _dirty = false;
      Navigator.pop(context);
      return true;
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('초안을 삭제하지 못했습니다. $e')));
      return false;
    } finally {
      _confirmingExit = false;
    }
  }
  Widget _build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) {
    if (!didPop) unawaited(_confirmExit());
  }, child: Scaffold(appBar: AppBar(centerTitle: false, toolbarHeight: _wide ? null : 52, titleSpacing: 0, leadingWidth: 44, title: const WorkspaceTitle('문서 작성'), actions: [IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(36, 40), maximumSize: const Size(36, 40), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Row(mainAxisSize: MainAxisSize.min, children: [const KeyboardDismissAction(), const DesktopMenuAction(), if(widget.onReload!=null)IconButton(tooltip:'서버 자료 갱신',onPressed:_reload,icon:const Icon(Icons.refresh)), IconButton(tooltip: _preview ? '편집' : '미리보기', icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined), onPressed: () { _highlightReference(null); _syntaxTooltip.hide(); _togglePreview(); }), IconButton(tooltip: '저장', icon: const Icon(Icons.save_outlined), onPressed: _canEdit && !_saving ? _save : null),
    if (!_preview && widget.storage?.documentAiRequest != null && _canEdit)
      IconButton(tooltip: 'AI 문장 생성', icon: const Icon(Icons.auto_awesome_outlined), onPressed: _saving ? null : _openAi),
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
      final documentBody = _preview
        ? documentReadingView(context, DocumentSegment(_body.text, _body.bindings), _previewRevision, _dirty)
        : !_canEdit
        ? SingleChildScrollView(child:SelectableText(_body.text))

        : _rich
        ? DocumentRichEditor(key: ValueKey(_richInsertionRevision), readOnly: _saving, onInsertFootnote: _saving ? null : _insertFootnote, onInsertTable: _saving ? null : (offset) => _insertTable(richOffset: offset), onInsertPhoto: _saving ? null : _insertPhoto, onInsertDivider: _saving ? null : (offset) => _insertVisualBlock(offset, documentDivider), onEditLines: _editLines, sourceSelection: _richLineSelection, onCaretChanged: (offset) => _richAiCaret = offset, source: _body.text, links: _body.bindings, onPatch: _applyRichPatch, onLinkHover: _highlightReference, modeSwitch: modeSwitch, dirty: _dirty, diagnostics: _body.syntaxDiagnostics, onSyntaxDiagnostic: _showSyntaxDiagnostic)
        : DocumentLineNumbers(controller: _body, scroll: _documentScroll, child: CaretAssist(controller: _body, focus: _bodyFocus, useThoughtLabels: true, selectionAssist: true, documentSyntax: !_saving,
          words: labelAssistTargets(excludeProject: widget.project), onWord: _insertLabel,
          tags: elements.tags.toList(), onTag: _insertTag,
          showWhenEmpty: false, enterSelectsVisible: true, showShortcutHint: true,
          child: Stack(fit:StackFit.expand,children:[Listener(
          onPointerDown: (event) {
            _syntaxTouch = event.kind == PointerDeviceKind.touch ? event.position : null;
            _syntaxTooltip.hide();
          },
          child: CallbackShortcuts(bindings: {for (final entry in documentLineShortcuts.entries) entry.key: () => _editLines(entry.value, _body.selection)}, child: TextField(key: const ValueKey('project-document'), readOnly: _saving, controller: _body, focusNode: _bodyFocus, scrollController: _documentScroll, expands: true, minLines: null, maxLines: null,
          onTapOutside: _wide ? null : (_) {},
          inputFormatters: const [DocumentListInput()],
          onTap: _tapSource, textAlignVertical: TextAlignVertical.top, keyboardType: TextInputType.multiline,
          decoration: InputDecoration(contentPadding:EdgeInsets.fromLTRB(12,16,12,_dirty?36:16),fillColor: Theme.of(context).colorScheme.surfaceContainerHighest, hoverColor: Colors.transparent, focusColor: Colors.transparent, hintText: '본문을 작성하세요. 라벨 링크: [[표시명|라벨]]', border: const OutlineInputBorder())))),
          if(_dirty)const Positioned(left:12,right:12,bottom:8,child:IgnorePointer(child:Text('아직 저장되지 않았습니다.',textAlign:TextAlign.center,style:TextStyle(color:Colors.red,fontSize:12)))),
        ])));
      final documentInput = !_canEdit || _preview || _rich ? documentBody : DragTarget<Object>(key: const ValueKey('document-link-drop'),
        onWillAcceptWithDetails: (details) => !_saving && _dragKey(details.data) != null,
        onAcceptWithDetails: _dropLink, builder: (context, candidates, rejected) => KeyedSubtree(key: _dropEditorKey, child: documentBody));
      final panel = Material(key: const ValueKey('project-reference-panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(4), child: _wide ? _desktopReferencePanels() : _referenceList()));
      final document = Column(children: [
        if (!_preview && !_rich && _canEdit) DocumentEditorToolbar(
          key: const ValueKey('document-editor-toolbar'),
          modeSwitch: modeSwitch,
          tools: [
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
        Expanded(child: Padding(padding: EdgeInsets.fromLTRB(_wide ? 12 : 6, _wide ? 2 : 0, _wide ? 12 : 6, 0), child: _wide
          ? Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Expanded(child:document),if(_thoughtPanelOpen)...[const SizedBox(width:12),SizedBox(width:(constraints.maxWidth*.45).clamp(300.0,560.0),child:panel)],SizedBox(width:32,child:Align(alignment:Alignment.centerRight,child:IconButton(key:const ValueKey('project-thought-panel-toggle'),tooltip:_thoughtPanelOpen?'생각 패널 숨기기':'생각 패널 보이기',padding:EdgeInsets.zero,onPressed:()=>setState(()=>_thoughtPanelOpen=!_thoughtPanelOpen),icon:Icon(_thoughtPanelOpen?Icons.chevron_right:Icons.chevron_left))))])
          : _mobileDocumentSplit(document, panel))),
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
      '주석: <!-- 한 줄 또는 여러 줄 주석 -->\n\n'
      '구분선: ----- (기본 60%), -----10----- (너비 10%)\n\n'
      '왼쪽 정렬: |텍스트 |\n오른쪽 정렬: | 텍스트|\n가운데 정렬: | 텍스트 |\n\n'
      '링크: [[표시명|라벨 또는 문서 제목]]\n웹 링크: [[표시명|https://example.com]]\n'
      '[[표시명|까지 입력하면 어시스트가 열립니다. Ctrl + Space로 선택할 수 있습니다. 문서는 문서: 접두어와 굵은 제목으로 표시됩니다.\n\n'
      '표: 상단 표 삽입 버튼에서 행·열과 내용을 입력하세요. 삽입 후 본문에서 수정하며 미리보기에서 표로 표시됩니다.\n| 제목 | 제목 |\n| --- | --- |\n| 내용 | 내용 |\n\n'
      '코드: <code>code</code>\n언어 표시: <code lang="python">code</code>\n여러 줄도 가능하며 코드 안의 문법은 해석하지 않습니다.\n\n'
      '상단 미리보기 버튼으로 서식과 링크를 확인하세요.')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  ));
}

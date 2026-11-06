import 'workspace_routes.dart';
import 'desktop_menu_frame.dart';
import 'graph_layout.dart';
import 'keyboard_viewport.dart';
import 'inline_tags.dart';
import 'limited_rows_wrap.dart';
import 'caret_assist.dart';
import 'element_binding.dart';
import 'paragraph_tag_input.dart';
import 'memo_boxes.dart';
import 'tag_colors.dart';
import '../../app_theme.dart';
import 'project_folders.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'workspace_storage.dart';
import 'hashtags.dart';
import 'tag_page.dart';

import 'paragraph_editor.dart';
import 'word_badge.dart';
import 'project_page.dart';
import 'project_builder.dart';
import 'all_thoughts_page.dart';
import 'workspace_menu.dart';
import 'element_store.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    this.storage,
    required this.themeMode,
    this.lightPalette = LightPalette.neutral,
    this.onLightPaletteChanged,
    required this.onThemeChanged,
  });
  final WorkspaceStorage? storage;
  final ThemeMode themeMode;
  final LightPalette lightPalette;
  final ValueChanged<LightPalette>? onLightPaletteChanged;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final _draft = BoundTextController('', const []);
  final _draftTags = <String>{};
  final _draftConnections = <String>{};
  DateTime? _tagCommitUntil;
  final _focus = FocusNode();
  final _bodyKey = GlobalKey();
  final _quickAssistKey = GlobalKey<CaretAssistState>();
  final List<Note> _notes = [];
  String _query = '';
  int _memoRows = 5, _paragraphLimit = 5, _projectLimit = 5;
  bool _memoHasMore = false;
  bool get _menuVisible => desktopMenu.visible;
  set _menuVisible(bool value) => desktopMenu.setVisible(value);
  bool _pendingImeSave = false;
  bool _pendingImeNewline = false, _finishingImeNewline = false;
  int _imeNewlineLines = 0;
  String? _newlineEchoBefore, _newlineEchoAfter;
  TextEditingValue? _assistInputBefore, _assistCompleted;
  DateTime? _assistSubmitUntil;
  DateTime? _newlineEchoUntil;
  bool _platformEnterQueued = false;
  String? _enterEchoText;
  DateTime? _enterEchoUntil, _explicitNewlineUntil;
  bool get _desktopQuickMemo => defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux;
  Note? _editing;
  String? _storageError;
  bool _restoreBlocked = false;
  @override
  void initState() {
    super.initState();
    desktopMenu.visible = true;
    _draft.addListener(_imeUpdated);
    projectFolders.clear();
    paragraphFolders.clear();
    elementFolders.clear();
    hiddenSearchTags.clear();
    hashtagFolders.clear();
    hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
    pageGraphLayout = GraphLayout();
    memoBoxFolders.clear();
    elements.addListener(_elementDeleted);
    elements.onProjectChanged = _persist;
    elements.availableParagraphs = () => _availableParagraphs;
    elements.onRenamed = _elementRenamed;
    try {
      final raw = widget.storage?.read();
      if (raw != null) {
        final snapshot = WorkspaceSnapshot.decode(raw);
        snapshot.apply();
        _notes.addAll(snapshot.notes);
        final layouts = widget.storage?.readGraphLayouts();
        if (layouts != null) {
          try { restoreGraphLayouts(layouts, {for (final box in memoBoxes) box.name: box.layout}); }
          catch (_) { /* Keep the layout included in the workspace snapshot. */ }
        }
        for (final note in _notes.where((n) => n.project == null && n.paragraphs != null)) {
          final record = elements.add(note.content);
          record.tags.addAll({...note.tags, ...note.paragraphs!.expand((p) => p.tags)});
          record.folder ??= note.folder;
          elements.connect(record.id, note.paragraphs!.expand((p) => p.bindings.map((b) => b.id)));
          note.paragraphs = null;
          note.bindings = [];
        }
      }
    } catch (_) {
      _restoreBlocked = true;
      _storageError = '브라우저 저장 데이터를 읽지 못했습니다. 기존 데이터는 보존되며 새 저장은 중단됩니다.';
    }
  }

  void _elementRenamed(String oldText, String newText) {
    for (final note in _notes) {
      if (note.project == null && note.paragraphs == null && note.bindings.isNotEmpty) {
        final previous = note.content;
        final controller = BoundTextController(previous, note.bindings)
          ..sync({for (final record in elements.records.values) record.id: record.text});
        final owner = elements.records[previous];
        final collision = elements.records[controller.text];
        if (owner == null || collision == null || identical(owner, collision)) {
          if (owner != null && previous != controller.text) {
            elements.records.remove(previous);
            owner.text = controller.text;
            elements.records[owner.text] = owner;
            renameWordColor(previous, owner.text);
          }
          note.content = controller.text;
          note.bindings = List.of(controller.bindings);
        }
        controller.dispose();
      }
      final paragraphs = note.project?.paragraphs ?? note.paragraphs;
      if (paragraphs != null) {
        final records = {for (final record in elements.records.values) record.id: record.text};
        for (var i = 0; i < paragraphs.length; i++) {
          final paragraph = paragraphs[i];
          if (paragraph.bindings.isEmpty) continue;
          final controller = BoundTextController(paragraph.text, paragraph.bindings)..sync(records);
          paragraphs[i] = Paragraph(controller.text, paragraph.role, tags: paragraph.tags, bindings: List.of(controller.bindings));
          controller.dispose();
        }
        note.content = paragraphs.map((p) => p.text).join('\n\n');
        if (note.project != null) elements.indexProject(note.project!);
      }
      if (note.project == null &&
          note.paragraphs == null &&
          note.content == oldText) {
        note.content = newText;
      }
      final words = note.project?.words;
      if (words != null) {
        for (var i = 0; i < words.length; i++) {
          if (words[i] == oldText) words[i] = newText;
        }
      }
    }
  }

  void _elementDeleted() {
    _draft.sync({for (final record in elements.records.values) record.id: record.text});
    setState(() {
      _notes.removeWhere(
        (n) =>
            n.project == null &&
            n.paragraphs == null &&
            !elements.records.containsKey(n.content),
      );
      for (final note in _notes) {
        note.project?.words.removeWhere(
          (w) => !elements.records.containsKey(w),
        );
      }
      if (_editing != null && !_notes.contains(_editing)) {
        _editing = null;
        _draft.clear();
      _draftTags.clear();
      _draftConnections.clear();
      }
    });
    _persist();
  }

  Future<void> _createFolder({bool tag = false, String? kind}) async {
    var folderName = '';
    var closed = false;
    final name = await showDialog<String>(context: context, builder: (dialogContext) {
      void finish(String? value) {
        if (closed || !dialogContext.mounted) return;
        closed = true;
        Navigator.pop(dialogContext, value);
      }
      return CallbackShortcuts(bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => finish(folderName.trim()),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => finish(folderName.trim()),
        const SingleActivator(LogicalKeyboardKey.escape): () => finish(null),
      }, child: AlertDialog(
        title: Text(tag ? '해시태그 폴더 만들기' : kind == 'paragraph' ? '문단 폴더 만들기' : kind == 'box' ? '메모상자 폴더 만들기' : kind == 'element' ? '원소 폴더 만들기' : '폴더 만들기'),
        content: TextField(onChanged: (value) => folderName = value, autofocus: true,
          decoration: const InputDecoration(labelText: '폴더 이름'), textInputAction: TextInputAction.done,
          onSubmitted: (value) => finish(value.trim())),
        actions: [
          TextButton(onPressed: () => finish(null), child: const Text('취소')),
          TextButton(onPressed: () => finish(folderName.trim()), child: const Text('만들기')),
        ],
      ));
    });
    if (!mounted || name == null || name.isEmpty) return;
    final folders = kind == 'box' ? memoBoxFolders : tag ? hashtagFolders : kind == 'paragraph' ? paragraphFolders : kind == 'element' ? elementFolders : projectFolders;
    if (!folders.contains(name)) {
      setState(() => folders.add(name));
      await _persist();
    }
  }

  void _moveProject(List<Note> projects, int index, String? folder) {
    setState(() => projects[index].project!.folder = folder);
    _persist();
  }

  void _moveTag(String tag, String? folder) {
    setState(() {
      if (folder == null) {
        hashtagFolderAssignments.remove(tag);
      } else {
        hashtagFolderAssignments[tag] = folder;
      }
    });
    _persist();
  }

  Future<void> _persistLayouts() async {
    if (widget.storage == null || _restoreBlocked) return;
    try {
      await widget.storage!.writeGraphLayouts(encodeGraphLayouts({for (final box in memoBoxes) box.name: box.layout}));
    } catch (_) {
      if (mounted) setState(() => _storageError = '화면 배치를 저장하지 못했습니다. 브라우저의 사이트 저장 공간을 확인해주세요.');
    }
  }

  Future<void> _persist() async {
    if (widget.storage == null || _restoreBlocked) return;
    try {
      for (final note in _notes.where((n) => n.project != null)) { note.content = note.project!.content; }
      final workspaceSave = widget.storage!.write(WorkspaceSnapshot.encode(_notes));
      final layoutSave = _persistLayouts();
      await workspaceSave;
      await layoutSave;
    } catch (_) {
      if (mounted) {
        setState(
          () => _storageError = '브라우저 저장에 실패했습니다. 브라우저의 사이트 저장 공간 설정을 확인해주세요.',
        );
      }
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 데이터를 초기화할까요?'),
        content: const Text('원소·문단·프로젝트·폴더와 이 브라우저에 저장된 앱 데이터를 삭제합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('모두 삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.storage?.clear();
      if (!mounted) return;
      setState(() {
        projectFolders.clear();
      paragraphFolders.clear();
      elementFolders.clear();
      hiddenSearchTags.clear();
        hashtagFolders.clear();
        hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
    pageGraphLayout = GraphLayout();
    memoBoxFolders.clear();
        elements.clear();
        restoreWordColors({});
        _notes.clear();
        _draft.clear();
      _draftTags.clear();
      _draftConnections.clear();
        _editing = null;
        _storageError = null;
        _restoreBlocked = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('메모리와 기기 저장 데이터를 초기화했습니다.')));
    } catch (_) {
      if (mounted) {
        setState(() => _storageError = '기기 데이터 삭제에 실패했습니다. 다시 시도해주세요.');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => desktopMenu.detach(this));
    elements.removeListener(_elementDeleted);
    elements.onProjectChanged = null;
    elements.availableParagraphs = null;
    elements.onRenamed = null;
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitQuickMemo() {
    if (_tagCommitUntil != null && DateTime.now().isBefore(_tagCommitUntil!)) return;
    if (_assistSubmitUntil != null && DateTime.now().isBefore(_assistSubmitUntil!)) return;
    if (_pendingImeNewline || (_explicitNewlineUntil != null && DateTime.now().isBefore(_explicitNewlineUntil!))) return;
    if (_quickAssistKey.currentState?.acceptVisibleCandidate() == true) return;
    final tagToken = tagPrefix(_draft.value);
    if (tagToken.isNotEmpty) {
      final query = tagToken.substring(1);
      final candidates = wordSuggestions(_allTags, query);
      if (candidates.isNotEmpty || query.isNotEmpty) {
        _acceptQuickAssist(() => _insertQuickTag(candidates.isNotEmpty ? candidates.first : query));
      }
      return;
    }
    if (_draft.text.trim().isEmpty) return;
    _enterEchoText = _draft.text;
    _enterEchoUntil = DateTime.now().add(const Duration(milliseconds: 250));
    _save();
  }

  void _queuePlatformEnter() {
    if (_platformEnterQueued) return;
    _platformEnterQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _platformEnterQueued = false;
      if (mounted && _focus.hasFocus) _submitQuickMemo();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  TextEditingValue _formatQuickMemo(TextEditingValue oldValue, TextEditingValue value) {
    if (!_desktopQuickMemo) return value;
    final now = DateTime.now();
    final beforeAssist = _assistInputBefore, completedAssist = _assistCompleted;
    if (_assistSubmitUntil != null && now.isBefore(_assistSubmitUntil!) && beforeAssist != null && completedAssist != null &&
        oldValue.text == completedAssist.text) {
      String newline(TextEditingValue v, String line) {
        final start = v.selection.isValid ? v.selection.start : v.text.length;
        final end = v.selection.isValid ? v.selection.end : start;
        return v.text.replaceRange(start, end, line);
      }
      if (value.text == beforeAssist.text || [newline(beforeAssist, '\n'), newline(beforeAssist, '\r\n'),
        newline(completedAssist, '\n'), newline(completedAssist, '\r\n')].contains(value.text)) {
        return completedAssist;
      }
    }
    if (_newlineEchoUntil != null && now.isBefore(_newlineEchoUntil!) && oldValue.text == _newlineEchoAfter &&
        (value.text == _newlineEchoBefore || value.text == '$_newlineEchoAfter\n' || value.text == '$_newlineEchoAfter\r\n')) {
      return oldValue.copyWith(composing: TextRange.empty);
    }
    if (_pendingImeNewline || (value.composing.isValid && !value.composing.isCollapsed)) return value;
    if (oldValue.text.isEmpty && _enterEchoUntil != null && now.isBefore(_enterEchoUntil!) &&
        (value.text == '$_enterEchoText\n' || value.text == '$_enterEchoText\r\n' || value.text == '\n')) {
      _enterEchoText = null;
      return oldValue;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed || keyboard.isAltPressed || keyboard.isControlPressed || keyboard.isMetaPressed ||
        (_explicitNewlineUntil != null && now.isBefore(_explicitNewlineUntil!))) { return value; }
    var start = 0;
    while (start < oldValue.text.length && start < value.text.length && oldValue.text[start] == value.text[start]) { start++; }
    var oldEnd = oldValue.text.length, newEnd = value.text.length;
    while (oldEnd > start && newEnd > start && oldValue.text[oldEnd - 1] == value.text[newEnd - 1]) { oldEnd--; newEnd--; }
    final inserted = value.text.substring(start, newEnd);
    if (inserted == '\n' || inserted == '\r\n') {
      _queuePlatformEnter();
      return oldValue.copyWith(composing: TextRange.empty);
    }
    if (oldValue.composing.isValid && !oldValue.composing.isCollapsed && inserted.endsWith('\n')) {
      final length = inserted.endsWith('\r\n') ? 2 : 1;
      final text = value.text.replaceRange(newEnd - length, newEnd, '');
      _queuePlatformEnter();
      return value.copyWith(text: text, selection: TextSelection.collapsed(offset: (value.selection.extentOffset - length).clamp(0, text.length)), composing: TextRange.empty);
    }
    return value;
  }

  void _imeUpdated() {
    if (_pendingImeNewline && _draft.value.composing.isCollapsed) _finishImeNewline();
    if (_pendingImeSave && _draft.value.composing.isCollapsed) {
      _finishImeSave();
    }
  }

  void _insertQuickNewline() {
    final value = _draft.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    _explicitNewlineUntil = DateTime.now().add(const Duration(milliseconds: 250));
    setState(() => _draft.value = TextEditingValue(text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1)));
    _newlineEchoBefore = value.text;
    _newlineEchoAfter = _draft.text;
    _newlineEchoUntil = _explicitNewlineUntil;
  }

  void _finishImeNewline() {
    if (_finishingImeNewline) return;
    _finishingImeNewline = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishingImeNewline = false;
      if (!mounted || !_pendingImeNewline) return;
      _pendingImeNewline = false;
      if (!_focus.hasFocus) return;
      _draft.clearComposing();
      // Some IMEs commit only the syllable; others also insert the newline.
      if (_draft.text.split('\n').length <= _imeNewlineLines) _insertQuickNewline();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _finishImeSave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingImeSave) return;
      _pendingImeSave = false;
      if (!_focus.hasFocus) return;
      _draft.clearComposing();
      _submitQuickMemo();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _quickMemoKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && (!{
      LogicalKeyboardKey.process, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
    }.contains(event.logicalKey) || event.physicalKey == PhysicalKeyboardKey.backspace ||
        event.physicalKey == PhysicalKeyboardKey.delete)) {
      if (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter &&
          event.physicalKey != PhysicalKeyboardKey.enter && event.physicalKey != PhysicalKeyboardKey.numpadEnter) {
        _tagCommitUntil = null;
      }
      _newlineEchoBefore = null; _newlineEchoAfter = null; _newlineEchoUntil = null;
      _assistSubmitUntil = null; _assistInputBefore = null; _assistCompleted = null;
    }
    final enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter ||
      event.physicalKey == PhysicalKeyboardKey.enter || event.physicalKey == PhysicalKeyboardKey.numpadEnter;
    if (!_desktopQuickMemo || !enter) {
      return KeyEventResult.ignored;
    }
    // A new Enter that bubbles past assist is a distinct save request.
    if (event is KeyDownEvent) {
      _assistSubmitUntil = null; _assistInputBefore = null; _assistCompleted = null;
    }
    if (event is KeyUpEvent) {
      if (_pendingImeSave) _finishImeSave();
      if (_pendingImeNewline) _finishImeNewline();
      return HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed
          ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    final value = _draft.value;
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent && !keyboard.isShiftPressed && !keyboard.isAltPressed &&
        !keyboard.isControlPressed && !keyboard.isMetaPressed &&
        _quickAssistKey.currentState?.acceptVisibleCandidate() == true) {
      _pendingImeSave = false;
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (!keyboard.isShiftPressed && !keyboard.isAltPressed) _explicitNewlineUntil = null;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (keyboard.isShiftPressed || keyboard.isAltPressed) {
        _pendingImeSave = false;
        _pendingImeNewline = true;
        _imeNewlineLines = value.text.split('\n').length;
        _explicitNewlineUntil = DateTime.now().add(const Duration(milliseconds: 250));
      } else {
        _pendingImeSave = true;
      }
      // Commit the final IME value before applying the captured save or newline intent.
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed || keyboard.isAltPressed) {
      _insertQuickNewline();
    } else if (value.text.trim().isNotEmpty) {
      _submitQuickMemo();
    }
    return KeyEventResult.handled;
  }

  void _acceptQuickAssist(VoidCallback action) {
    final before = _draft.value;
    action();
    _pendingImeSave = false;
    _assistInputBefore = before; _assistCompleted = _draft.value;
    _assistSubmitUntil = DateTime.now().add(const Duration(milliseconds: 500));
  }

  void _insertQuickElement(String word) {
    final selection = _draft.selection;
    final prefix = completionPrefix(_draft.value, elements.visibleWords);
    final start = (selection.isValid ? selection.start : _draft.text.length) - prefix.length;
    final end = selection.isValid ? selection.end : start;
    final record = elements.records[word];
    if (record == null) return;
    setState(() {
      _draftConnections.add(record.id);
      _draft.value = TextEditingValue(text: _draft.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start));
    });
    _focus.requestFocus();
  }

  void _insertQuickTag(String tag) {
    final token = tagPrefix(_draft.value);
    if (!token.startsWith('#')) return;
    final start = _draft.selection.start - token.length;
    setState(() {
      _draftTags.add(tag);
      _draft.value = TextEditingValue(text: _draft.text.replaceRange(start, _draft.selection.end, ''),
        selection: TextSelection.collapsed(offset: start));
    });
    _focus.requestFocus();
  }

  void _save() {
    _pendingImeSave = false;
    if (_draft.text.trim().isEmpty) return;
    var body = _draft.text;
    for (final link in _draft.bindings.reversed) { body = body.replaceRange(link.start, link.end, ''); }
    if (parseTaggedInput(body).text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('태그와 함께 원소 내용을 입력해주세요.')));
      return;
    }
    final input = [body, ..._draftTags.map((tag) => '#$tag')].join(' ');
    final record = elements.add(input, replaceTags: _editing != null);
    final links = <ElementBinding>[];
    elements.connect(record.id, {..._draftConnections, ..._draft.bindings.map((link) => link.id)});
    setState(() {
      if (_editing == null) {
        _notes.insert(0, Note(record.text)..bindings = links);
      } else {
        _editing!.content = record.text;
        _editing!.bindings = links;
      }
      _editing = null;
      _draft.clear();
      _draftTags.clear();
      _draftConnections.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('기록함에 담았어요. 다음 생각도 남겨보세요.')));
    _persist();
    _focus.requestFocus();
  }

  List<Note> get _paragraphNotes => _notes.where((n) => n.project == null && n.paragraphs != null).toList();
  void _moveParagraph(int index, String? folder) {
    setState(() => _paragraphNotes[index].folder = folder);
    _persist();
  }
  void _moveElement(int index, String? folder) {
    setState(() => elements.records[elements.words[index]]!.folder = folder);
    _persist();
  }

  List<Paragraph> get _availableParagraphs => _notes
      .where((n) => n.project == null && n.paragraphs != null)
      .map((n) => Paragraph(n.content, ParagraphRole.body, tags: Set.of(n.tags), bindings: n.paragraphs!.single.bindings)).toList();

  List<String> get _allTags => {...elements.tags, ..._notes.expand((n) => n.project?.tags ?? <String>{}),
    ..._notes.where((n) => n.project == null && n.paragraphs != null).expand((n) => n.tags)}.toList()..sort();

  Future<void> _allThoughts([MemoBox? box]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AllThoughtsPage(notes: _notes, onLayoutChanged: _persistLayouts, onChanged: _persist, initialBox: box)));
    if (mounted) setState(() {});
  }

  Future<void> _createProject() async {
    final available = _availableParagraphs;
    final words = elements.visibleWords;
    final project = await Navigator.push<WritingProject>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectBuilder(available: available, words: words),
      ),
    );
    if (project == null || !mounted) return;
    final note = Note(project.content)
      ..project = project
      ..paragraphs = project.paragraphs;
    setState(() => _notes.insert(0, note));
    await _persist();
    await _showProject(note);
  }

  Future<void> _showProject(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProjectPage(project: note.project!, available: _availableParagraphs, onChanged: _persist),
      ),
    );
    if (!mounted) return;
    setState(() {
      note.paragraphs = note.project!.paragraphs;
      note.content = note.project!.content;
    });
    await _persist();
  }

  Future<void> _open(Note note) async {
    if (note.project != null) {
      await _showProject(note);
      return;
    }
    if (note.paragraphs != null) {
      showElementMetadata(context, note.content);
      return;
    }
    if (_draft.text.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('작성 중인 내용을 바꿀까요?'),
          content: const Text('다른 메모를 열면 아직 담지 않은 내용이 사라져요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 작성'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('다른 메모 열기'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _editing = note;
      final tags = elements.records[note.content.trim()]?.tags ?? <String>{};
      _draftTags..clear()..addAll(tags);
      _draftConnections..clear()..addAll(elements.records[note.content.trim()]?.connections ?? <String>{});
      _draft.clear();
      _draft.text = note.content;
      _draft.bindings = List.of(note.bindings);
      _draft.sync({for (final record in elements.records.values) record.id: record.text});
    });
    _focus.requestFocus();
  }

  Future<void> _menu() async {
    FocusScope.of(context).unfocus();
    final projects = _notes.where((n) => n.project != null).toList();
    final tags = _allTags;
    final choice = await showDialog<int>(
      context: context,
      builder: (_) => WorkspaceMenu(
        projects: projects.map((n) => n.title).toList(),
        onPin: MediaQuery.sizeOf(context).width >= 1000
            ? () {
                Navigator.pop(context);
                setState(() => _menuVisible = true);
              }
            : null,
        tags: tags,
        paragraphs: _paragraphNotes.map((n) => n.title).toList(),
        paragraphFolders: paragraphFolders,
        paragraphFolderNames: _paragraphNotes.map((n) => n.folder).toList(),
        onParagraphMoved: _moveParagraph,
        elements: elements.words,
        elementFolders: elementFolders,
        elementFolderNames: elements.words.map((w) => elements.records[w]!.folder).toList(),
        onElementMoved: _moveElement,
        tagFolders: hashtagFolders,
        tagFolderNames: hashtagFolderAssignments,
        onProjectMoved: (index, folder) =>
            _moveProject(projects, index, folder),
        onTagMoved: _moveTag,
        onTagColorChanged: _persist,
        onBoxChanged: _persist,
        folders: projectFolders,
        projectFolderNames: projects.map((n) => n.project!.folder).toList(),
      ),
    );
    await _selectMenu(choice, projects, tags);
    if (mounted &&
        (choice == WorkspaceMenu.createFolder ||
            choice == WorkspaceMenu.createTagFolder ||
            choice == WorkspaceMenu.createParagraphFolder || choice == WorkspaceMenu.createElementFolder || choice == WorkspaceMenu.createBoxFolder)) {
      await _menu();
    }
  }

  Future<void> _selectMenu(
    int? choice,
    List<Note> projects,
    List<String> tags,
  ) async {
    if (!mounted || choice == null || choice == -1) return;
    if (choice == WorkspaceMenu.createBoxFolder) { await _createFolder(kind: 'box'); return; }
    if (choice == WorkspaceMenu.createBox) {
      final box = await createMemoBox(context);
      if (box != null) { await _persist(); if (mounted) setState(() {}); }
      return;
    }
    if (choice <= -1100000 && choice > -2000000) {
      final index = -1100000 - choice;
      if (index < memoBoxes.length) {
        await _allThoughts(memoBoxes[index]);
      }
      return;
    }
    if (choice == WorkspaceMenu.allThoughts) { await _allThoughts(); return; }
    if (choice <= -3000000) {
      final index = -3000000 - choice;
      if (index < elements.words.length) showElementMetadata(context, elements.words[index]);
      return;
    }
    if (choice <= -2000000) {
      final index = -2000000 - choice;
      if (index < _paragraphNotes.length) showElementMetadata(context, _paragraphNotes[index].content);
      return;
    }
    if (choice == WorkspaceMenu.createParagraphFolder || choice == WorkspaceMenu.createElementFolder) {
      await _createFolder(kind: choice == WorkspaceMenu.createParagraphFolder ? 'paragraph' : 'element');
      return;
    }
    if (choice == WorkspaceMenu.createProject) {
      await _createProject();
      return;
    }
    if (choice == WorkspaceMenu.resetData) {
      await _reset();
      return;
    }
    if (choice == WorkspaceMenu.createFolder) {
      await _createFolder();
      return;
    }
    if (choice == WorkspaceMenu.createTagFolder) {
      await _createFolder(tag: true);
      return;
    }
    if (choice <= -3) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TagPage(tag: tags[-3 - choice], notes: _notes, onOpen: _open),
        ),
      );
    } else if (choice == -2) {
      await _allThoughts();
    } else {
      await _showProject(projects[choice]);
    }
  }

  Widget _themeChoice(BuildContext context, Object value, bool checked, Widget title) => ListTile(
    dense: true, selected: checked,
    leading: checked ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18),
    title: title, onTap: () => Navigator.pop(context, value),
  );

  Future<void> _showTheme() async {
    final choice = await showDialog<Object>(context: context, builder: (context) => Dialog(
      alignment: AlignmentDirectional.topEnd,
      insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 320, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('화면 모드')),
          _themeChoice(context, ThemeMode.system, widget.themeMode == ThemeMode.system, const Text('시스템 설정')),
          _themeChoice(context, ThemeMode.light, widget.themeMode == ThemeMode.light,
            Row(children: [const Expanded(child: Text('라이트')), PaletteSwatches(colors: widget.lightPalette.swatches)])),
          _themeChoice(context, ThemeMode.dark, widget.themeMode == ThemeMode.dark,
            Row(children: [const Expanded(child: Text('다크')), PaletteSwatches(colors: [weaverDarkColors.surface, weaverDarkColors.surfaceContainerHighest, weaverDarkColors.primary])])),
          const Divider(),
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text('라이트 컬러셋')),
          for (final palette in LightPalette.values) _themeChoice(context, palette, widget.lightPalette == palette,
            Row(children: [Expanded(child: Text(palette.label)), PaletteSwatches(colors: palette.swatches)])),
          const SizedBox(height: 8),

        ],
      ))),
    ));
    if (!mounted) return;
    if (choice is ThemeMode) widget.onThemeChanged(choice);
    if (choice is LightPalette) widget.onLightPaletteChanged?.call(choice);
  }

  ColorScheme get colors => Theme.of(context).colorScheme;

  Widget _composer(double maxHeight) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).width < 760 ? double.infinity : maxHeight),
    child: Card(
    color: colors.surfaceContainerLow,
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded),
              const SizedBox(width: 8),
              Text(
                _editing == null ? '빠른 메모' : '메모 다듬기',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_draftTags.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: InlineTags(tags: _draftTags, onRemove: (tag) => setState(() => _draftTags.remove(tag))))),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            fit: FlexFit.loose,
            child: Focus(
            key: const ValueKey('quick-memo-keyboard'),
            canRequestFocus: false,
            onKeyEvent: _quickMemoKey,
            child: CaretAssist(key: _quickAssistKey, controller: _draft, focus: _focus, words: elements.visibleWords, showWhenEmpty: false,
              mobileViewportKey: _bodyKey,
              tags: {..._allTags, ..._draftTags}.toList()..sort(), enterSelectsVisible: true,
              onTag: (tag) => _acceptQuickAssist(() => _insertQuickTag(tag)),
              onWord: (word) => _acceptQuickAssist(() => _insertQuickElement(word)), child: TextField(
              key: const ValueKey('quick-memo'),
              inputFormatters: [TextInputFormatter.withFunction(_formatQuickMemo)],
              textInputAction: _desktopQuickMemo ? TextInputAction.done : TextInputAction.newline,
              onEditingComplete: _desktopQuickMemo ? () {} : null,
              onSubmitted: _desktopQuickMemo ? (_) => _submitQuickMemo() : null,
              controller: _draft,
              focusNode: _focus,
              minLines: 4,
              maxLines: MediaQuery.sizeOf(context).width < 760 ? 4 : null,
              onChanged: (_) {
                final completed = takeCompletedParagraphTags(_draft.value);
                setState(() {
                  if (completed.tags.isNotEmpty) {
                    _tagCommitUntil = DateTime.now().add(const Duration(milliseconds: 500));
                  }
                  _draftTags.addAll(completed.tags);
                  if (completed.tags.isNotEmpty) _draft.value = completed.value;
                });
              },
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '단어나 생각을 남겨보세요 #독서 #아이디어',
                contentPadding: EdgeInsets.zero,
              ),
            )),
          ),
          ),
          const SizedBox(height: 12),
          if (_draftConnections.isNotEmpty) ...[
            ConstrainedBox(constraints: const BoxConstraints(maxHeight: 66),
              child: SingleChildScrollView(child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final record in elements.records.values.where((r) => _draftConnections.contains(r.id)))
                  WordBadge(compact: true, word: record.text, onTap: () => showElementMetadata(context, record.text),
                    onLongPress: () => setState(() => _draftConnections.remove(record.id))),
              ]))),
            const SizedBox(height: 8),
          ],
          Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              textStyle: const TextStyle(fontSize: 12), visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _draft.text.trim().isEmpty ? null : _save,
            icon: const Icon(Icons.arrow_downward_rounded, size: 16),
            label: const Text('저장'),
          )),
        ],
      ),
    ),
  ));

  Widget _list() {
    final visible = _notes
        .where((n) => n.content.toLowerCase().contains(_query.toLowerCase()) || n.title.toLowerCase().contains(_query.toLowerCase()) || n.tags.any((t) => t.contains(_query.toLowerCase().replaceFirst('#', ''))))
        .toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final query = _query.toLowerCase().replaceFirst('#', '');
    final records = elements.records.values.where((record) => elements.isSearchable(record.text) &&
      (record.text.toLowerCase().contains(_query.toLowerCase()) || record.tags.any((tag) => tag.contains(query))))
      .toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final paragraphs = visible.where((note) => note.paragraphs != null && note.project == null).toList();
    final projects = visible.where((note) => note.project != null).toList();
    final moreStyle = TextButton.styleFrom(textStyle: const TextStyle(fontSize: 11),
      minimumSize: const Size(0, 24), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final badges = [for (final record in records) WordBadge(
      word: record.text, query: _query,
      onLongPress: () => showElementMetadata(context, record.text),
      onTap: () => showElementMetadata(context, record.text))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('모아둔 생각', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('${_notes.length}', style: TextStyle(color: colors.primary)),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('note-search'),
          onChanged: (value) => setState(() {
            _query = value; _memoRows = 5; _paragraphLimit = 5; _projectLimit = 5; _memoHasMore = false;
          }),
          decoration: const InputDecoration(
            hintText: '메모에서 찾기',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        if (visible.isEmpty && records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 40, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  _notes.isEmpty ? '아직 메모가 없어요' : '일치하는 메모가 없어요',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _notes.isEmpty ? '첫 메모를 남겨보세요.' : '다른 단어로 찾아보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
                ),
              ],
            ),
          ),
        if (_query.isEmpty) ClipRect(child: LimitedRowsWrap(
          key: const ValueKey('recent-memo-badges'), maxRows: _memoRows,
          onOverflowChanged: (overflow) { if (mounted && _memoHasMore != overflow) setState(() => _memoHasMore = overflow); },
          children: badges))
        else Wrap(spacing: 6, runSpacing: 6, children: badges),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_query.isEmpty && _memoHasMore) TextButton(key: const ValueKey('thoughts-more'), style: moreStyle,
            onPressed: () => setState(() => _memoRows += 5), child: const Text('+더보기')),
          TextButton(key: const ValueKey('thoughts-all'), style: moreStyle,
            onPressed: _allThoughts, child: const Text('모두보기')),
        ]),
        for (final isProject in [true]) ...[
          if ((isProject ? projects : paragraphs).isNotEmpty) ...[
            Divider(key: ValueKey(isProject ? 'main-project-divider' : 'main-paragraph-divider'),
              height: 18, thickness: 1, color: colors.outlineVariant.withValues(alpha: .45)),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(isProject ? '프로젝트' : '문단', style: Theme.of(context).textTheme.labelMedium)),
            for (final note in (isProject ? projects : paragraphs).take(_query.isNotEmpty
              ? (isProject ? projects.length : paragraphs.length) : (isProject ? _projectLimit : _paragraphLimit)))
              _recentNoteCard(note),
            if (_query.isEmpty && (isProject ? projects.length > _projectLimit : paragraphs.length > _paragraphLimit))
              Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(
                key: ValueKey(isProject ? 'projects-more' : 'paragraphs-more'), style: moreStyle,
                onPressed: () => setState(() { if (isProject) { _projectLimit += 5; } else { _paragraphLimit += 5; } }),
                child: const Text('+더보기'))),
          ],
        ],
      ],
    );
  }

  Widget _recentNoteCard(Note note) => Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            color: colors.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              minVerticalPadding: 4,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${note.createdAt.month}월 ${note.createdAt.day}일 · ${note.project != null ? '프로젝트' : '문단'}${note.tags.isEmpty ? '' : ' · ${note.tags.map((t) => '#$t').join(' ')}'}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _open(note),
            ),
          );

  Widget _desktopSidebar(BuildContext context) => SafeArea(
              child: WorkspaceMenu(
                embedded: true,
                onFloat: () { setState(() => _menuVisible = false); _menu(); },
                onHide: () => setState(() => _menuVisible = false),
                projects: _notes
                    .where((n) => n.project != null)
                    .map((n) => n.title)
                    .toList(),
                projectFolderNames: _notes
                    .where((n) => n.project != null)
                    .map((n) => n.project!.folder)
                    .toList(),
                paragraphs: _paragraphNotes.map((n) => n.title).toList(),
        paragraphFolders: paragraphFolders,
        paragraphFolderNames: _paragraphNotes.map((n) => n.folder).toList(),
        onParagraphMoved: _moveParagraph,
        elements: elements.words,
        elementFolders: elementFolders,
        elementFolderNames: elements.words.map((w) => elements.records[w]!.folder).toList(),
        onElementMoved: _moveElement,
        tagFolders: hashtagFolders,
                tagFolderNames: hashtagFolderAssignments,
                onProjectMoved: (index, folder) => _moveProject(
                  _notes.where((n) => n.project != null).toList(),
                  index,
                  folder,
                ),
                onTagMoved: _moveTag,
        onTagColorChanged: _persist,
        onBoxChanged: _persist,
                folders: projectFolders,
                tags: _allTags,
                onSelected: (choice) => _selectMenu(
                  choice,
                  _notes.where((n) => n.project != null).toList(),
                  _allTags,
                ),
              ),
            );

  @override
  Widget build(BuildContext context) {
    desktopMenu.attach(this, _desktopSidebar, _menu, () => mounted, notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) desktopMenu.attach(this, _desktopSidebar, _menu, () => mounted); });
    for (final note in _notes) {
      if (note.project != null) elements.indexProject(note.project!);
    }
    elements.sources[this] = [
      for (var i = 0; i < _notes.length; i++)
        if (_notes[i].paragraphs != null && _notes[i].project == null)
          ElementSource(
            '독립 문단 ${i + 1}: ${_notes[i].title}',
            _notes[i].content,
          ),
    ];
    final rawMedia = MediaQuery.of(context);
    final media = rawMedia.copyWith(viewInsets: rawMedia.viewInsets.copyWith(bottom: effectiveKeyboardInset(rawMedia)));
    return MediaQuery(data: media, child: DesktopMenuFrame(child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MediaQuery.sizeOf(context).width >= 1000 && _menuVisible
              ? '메뉴 숨기기'
              : '메뉴 열기',
          onPressed: MediaQuery.sizeOf(context).width >= 1000 && _menuVisible
              ? () => setState(() => _menuVisible = false)
              : _menu,
          icon: const Icon(Icons.grid_view_rounded),
        ),
        actions: [
          IconButton(
            tooltip: '테마 선택',
            onPressed: _showTheme,
            icon: Icon(Theme.of(context).brightness == Brightness.dark
              ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
          ),
          const SizedBox(width: 12),
        ],
        title: GestureDetector(onTap: () => navigateHome(context), child: Text(
          'WEAVER',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        )),
        centerTitle: false,
      ),
      body: SizedBox(key: _bodyKey, child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SafeArea(
              child: LayoutBuilder(builder: (context, viewport) {
                // Reserve the heading, actions and scroll padding above the card.
                final composerHeight = (viewport.maxHeight - 140).clamp(180.0, double.infinity);
                return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '기록함',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _createProject,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                                size: 18,
                              ),
                              label: const Text('프로젝트 생성'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= 760
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                        child: _list(),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(child: _composer(composerHeight)),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _composer(composerHeight),
                                    const SizedBox(height: 24),
                                    _list(),
                                  ],
                                ),
                        ),
                        if (_storageError != null) ...[
                          const SizedBox(height: 16),
                          Text(_storageError!, style: TextStyle(color: colors.error, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              }),
            ),
          ),
        ],
      )),
    )));
  }
}

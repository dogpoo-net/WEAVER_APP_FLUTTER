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
import 'paragraph_page.dart';
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
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final List<Note> _notes = [];
  String _query = '';
  bool _menuVisible = true;
  bool _pendingImeSave = false;
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
    _draft.addListener(_imeUpdated);
    projectFolders.clear();
    paragraphFolders.clear();
    elementFolders.clear();
    hiddenSearchTags.clear();
    hashtagFolders.clear();
    hashtagFolderAssignments.clear();
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
      }
    } catch (_) {
      _restoreBlocked = true;
      _storageError = '브라우저 저장 데이터를 읽지 못했습니다. 기존 데이터는 보존되며 새 저장은 중단됩니다.';
    }
  }

  void _elementRenamed(String oldText, String newText) {
    for (final note in _notes) {
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
        title: Text(tag ? '해시태그 폴더 만들기' : kind == 'paragraph' ? '문단 폴더 만들기' : kind == 'element' ? '원소 폴더 만들기' : '폴더 만들기'),
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
    final folders = tag ? hashtagFolders : kind == 'paragraph' ? paragraphFolders : kind == 'element' ? elementFolders : projectFolders;
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

  Future<void> _persist() async {
    if (widget.storage == null || _restoreBlocked) return;
    try {
      await widget.storage!.write(WorkspaceSnapshot.encode(_notes));
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
        elements.clear();
        restoreWordColors({});
        _notes.clear();
        _draft.clear();
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
    elements.removeListener(_elementDeleted);
    elements.onProjectChanged = null;
    elements.availableParagraphs = null;
    elements.onRenamed = null;
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitQuickMemo() {
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
    if (!_desktopQuickMemo || (value.composing.isValid && !value.composing.isCollapsed)) return value;
    final now = DateTime.now();
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
    if (_pendingImeSave && _draft.value.composing.isCollapsed) {
      _finishImeSave();
    }
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
    if (!_desktopQuickMemo ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      if (_pendingImeSave) _finishImeSave();
      return HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed
          ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    final value = _draft.value;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (!keyboard.isShiftPressed && !keyboard.isAltPressed) _explicitNewlineUntil = null;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (!keyboard.isShiftPressed && !keyboard.isAltPressed) {
        _pendingImeSave = true;
      }
      // Let the IME commit first, then save its final editing value.
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed || keyboard.isAltPressed) {
      _explicitNewlineUntil = DateTime.now().add(const Duration(milliseconds: 250));
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : start;
      setState(
        () => _draft.value = TextEditingValue(
          text: value.text.replaceRange(start, end, '\n'),
          selection: TextSelection.collapsed(offset: start + 1),
        ),
      );
    } else if (value.text.trim().isNotEmpty) {
      _submitQuickMemo();
    }
    return KeyEventResult.handled;
  }

  void _save() {
    _pendingImeSave = false;
    if (_draft.text.trim().isEmpty) return;
    if (parseTaggedInput(_draft.text).text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('태그와 함께 원소 내용을 입력해주세요.')));
      return;
    }
    final record = elements.add(_draft.text, replaceTags: _editing != null);
    setState(() {
      if (_editing == null) {
        _notes.insert(0, Note(record.text));
      } else {
        _editing!.content = record.text;
      }
      _editing = null;
      _draft.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('기록함에 담았어요. 다음 생각도 남겨보세요.')));
    _persist();
    _focus.requestFocus();
  }

  Future<void> _writeParagraphs([Note? note]) async {
    final words = elements.visibleWords;
    final result = await Navigator.push<List<Paragraph>>(
      context,
      MaterialPageRoute(
        builder: (_) => ParagraphEditor(
          initial: note?.paragraphs ?? const [],
          initialTags: note?.tags ?? const {},
          words: words,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final paragraph = result.single;
    setState(() {
      if (note != null) {
        note.content = paragraph.text;
        note.paragraphs = [paragraph];
        note.tags..clear()..addAll(paragraph.tags);
      } else {
        _notes.insert(0, Note(paragraph.text)..paragraphs = [paragraph]..tags.addAll(paragraph.tags));
      }
    });
    await _persist();
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
      .map((n) => Paragraph(n.content, ParagraphRole.body, tags: Set.of(n.tags))).toList();

  List<String> get _allTags => {...elements.tags,
    ..._notes.where((n) => n.project == null && n.paragraphs != null).expand((n) => n.tags)}.toList()..sort();

  Future<void> _showParagraph(Note note) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ParagraphPage(
      note: note,
      onEdit: () => _writeParagraphs(note),
      onDelete: () async {
        setState(() => _notes.remove(note));
        await _persist();
      },
      onTag: (tag) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TagPage(
          tag: tag, notes: _notes, onOpen: _open)));
      },
    )));
    if (mounted) setState(() {});
  }

  Future<void> _allThoughts() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AllThoughtsPage(notes: _notes)));
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
    final note = Note(project.paragraphs.map((p) => p.text).join('\n\n'))
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
      note.content = note.paragraphs!.map((p) => p.text).join("\n\n");
    });
    await _persist();
  }

  Future<void> _open(Note note) async {
    if (note.project != null) {
      await _showProject(note);
      return;
    }
    if (note.paragraphs != null) {
      await _showParagraph(note);
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
      _draft.text = [note.content, ...tags.map((t) => '#$t')].join(' ');
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
        folders: projectFolders,
        projectFolderNames: projects.map((n) => n.project!.folder).toList(),
      ),
    );
    await _selectMenu(choice, projects, tags);
    if (mounted &&
        (choice == WorkspaceMenu.createFolder ||
            choice == WorkspaceMenu.createTagFolder ||
            choice == WorkspaceMenu.createParagraphFolder || choice == WorkspaceMenu.createElementFolder)) {
      await _menu();
    }
  }

  Future<void> _selectMenu(
    int? choice,
    List<Note> projects,
    List<String> tags,
  ) async {
    if (!mounted || choice == null || choice == -1) return;
    if (choice == WorkspaceMenu.allThoughts) { await _allThoughts(); return; }
    if (choice <= -3000000) {
      final index = -3000000 - choice;
      if (index < elements.words.length) showElementMetadata(context, elements.words[index]);
      return;
    }
    if (choice <= -2000000) {
      final index = -2000000 - choice;
      if (index < _paragraphNotes.length) await _showParagraph(_paragraphNotes[index]);
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
      await _writeParagraphs();
    } else {
      await _showProject(projects[choice]);
    }
  }

  ColorScheme get colors => Theme.of(context).colorScheme;

  Widget _composer() => Card(
    color: colors.surfaceContainerLow,
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
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
            ],
          ),
          const SizedBox(height: 14),
          Focus(
            canRequestFocus: false,
            onKeyEvent: _quickMemoKey,
            child: TextField(
              key: const ValueKey('quick-memo'),
              inputFormatters: [TextInputFormatter.withFunction(_formatQuickMemo)],
              textInputAction: _desktopQuickMemo ? TextInputAction.done : TextInputAction.newline,
              onEditingComplete: _desktopQuickMemo ? () {} : null,
              onSubmitted: _desktopQuickMemo ? (_) => _submitQuickMemo() : null,
              controller: _draft,
              focusNode: _focus,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '단어나 생각을 남겨보세요 #독서 #아이디어',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _draft.text.trim().isEmpty ? null : _save,
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                label: Text(_editing == null ? '저장' : '저장'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _list() {
    final visible = _notes
        .where((n) => n.content.toLowerCase().contains(_query.toLowerCase()) || n.tags.any((t) => t.contains(_query.toLowerCase().replaceFirst('#', ''))))
        .toList();
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
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: '메모에서 찾기',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        if (visible.isEmpty)
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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: elements.visibleWords
              .where(
                (word) => word.toLowerCase().contains(_query.toLowerCase()),
              )
              .map(
                (word) => WordBadge(
                  onLongPress: () => showElementMetadata(context, word),
                  word: word,
                  query: _query,
                  onTap: () {
                    showElementMetadata(context, word);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        for (final note in visible.where(
          (n) => n.paragraphs != null || n.project != null,
        ))
          Card(
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${note.createdAt.month}월 ${note.createdAt.day}일 · ${note.project != null ? '프로젝트' : '문단'}${note.tags.isEmpty ? '' : ' · ${note.tags.map((t) => '#$t').join(' ')}'}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _open(note),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
    return Scaffold(
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
          PopupMenuButton<Object>(
            tooltip: '테마 선택',
            initialValue: widget.themeMode,
            onSelected: (choice) {
              if (choice is ThemeMode) widget.onThemeChanged(choice);
              if (choice is LightPalette) widget.onLightPaletteChanged?.call(choice);
            },
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
            ),
            itemBuilder: (_) => [
              const PopupMenuItem<Object>(enabled: false, height: 32, child: Text('화면 모드')),
              CheckedPopupMenuItem<Object>(
                value: ThemeMode.system,
                checked: widget.themeMode == ThemeMode.system,
                child: const Text('시스템 설정'),
              ),
              CheckedPopupMenuItem(
                value: ThemeMode.light,
                checked: widget.themeMode == ThemeMode.light,
                child: Row(children: [const Expanded(child: Text('라이트')), PaletteSwatches(colors: widget.lightPalette.swatches)]),
              ),
              CheckedPopupMenuItem(
                value: ThemeMode.dark,
                checked: widget.themeMode == ThemeMode.dark,
                child: Row(children: [const Expanded(child: Text('다크')), PaletteSwatches(colors: [weaverDarkColors.surface, weaverDarkColors.surfaceContainerHighest, weaverDarkColors.primary])]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<Object>(enabled: false, height: 32, child: Text('라이트 컬러셋')),
              for (final palette in LightPalette.values) CheckedPopupMenuItem<Object>(
                value: palette, checked: widget.lightPalette == palette,
                child: Row(children: [Expanded(child: Text(palette.label)), PaletteSwatches(colors: palette.swatches)])),
            ],
          ),
          const SizedBox(width: 12),
        ],
        title: Text(
          'WEAVER',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (MediaQuery.sizeOf(context).width >= 1000 && _menuVisible)
            SafeArea(
              child: WorkspaceMenu(
                embedded: true,
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
                folders: projectFolders,
                tags: _allTags,
                onSelected: (choice) => _selectMenu(
                  choice,
                  _notes.where((n) => n.project != null).toList(),
                  _allTags,
                ),
              ),
            ),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
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
                            TextButton.icon(
                              onPressed: () => _writeParagraphs(),
                              icon: const Icon(Icons.subject, size: 18),
                              label: const Text('문단 쓰기'),
                            ),
                            TextButton.icon(onPressed: _allThoughts, icon: const Icon(Icons.bubble_chart_outlined),
                              label: const Text('모든 생각 보기')),
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
                                    Expanded(child: _composer()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _composer(),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

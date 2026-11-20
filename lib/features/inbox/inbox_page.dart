import '../capture/workspace_map_surface.dart';
import 'workspace_photo.dart';
import 'memo_box_actions.dart';
import '../capture/voice_transcription.dart';
import 'main_app_bar.dart';
import '../sync/workspace_events.dart';
import 'overview_collections.dart';
import 'memo_comments.dart';
import 'dart:async';
import 'label_links.dart';
import '../auth/google_auth.dart';
import '../sync/workspace_backup.dart';
import 'trash_page.dart';
import 'thought_settings.dart';
import '../capture/capture_models.dart';
import '../capture/location_capture.dart';
import '../capture/voice_dialog.dart';
import '../capture/voice_player.dart';
import '../capture/media_storage.dart';
import '../capture/photo_gallery.dart';
import 'package:image_picker/image_picker.dart';
import 'keyboard_dismiss.dart';
import 'workspace_routes.dart';
import 'desktop_menu_frame.dart';
import 'graph_layout.dart';
import 'keyboard_viewport.dart';
import 'packed_badges.dart';
import 'caret_assist.dart';
import 'element_binding.dart';
import 'document_syntax.dart';
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
import 'deferred_screen.dart';
import 'project_document_editor.dart' deferred as document_editor;
import 'all_thoughts_page.dart';
import 'workspace_menu.dart';
import 'element_store.dart';

part 'quick_memo_capture.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    this.storage,
    this.onSettingsImported,
    required this.themeMode,
    this.lightPalette = LightPalette.neutral,
    this.onLightPaletteChanged,
    this.darkPalette = DarkPalette.classic,
    this.onDarkPaletteChanged,
    required this.onThemeChanged,
  });
  final WorkspaceStorage? storage;
  final VoidCallback? onSettingsImported;
  final ThemeMode themeMode;
  final LightPalette lightPalette;
  final DarkPalette darkPalette;
  final ValueChanged<DarkPalette>? onDarkPaletteChanged;
  final ValueChanged<LightPalette>? onLightPaletteChanged;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver, _QuickMemoCapture<InboxPage> {
  final _bodyKey = GlobalKey();
  @override WorkspaceStorage? get _captureStorage => widget.storage;
  @override GlobalKey get _captureViewport => _bodyKey;
  @override bool get _captureBlocked => _restoreBlocked;
  @override Iterable<String> get _captureTags => _allTags;
  final List<Note> _notes = [];
  String _query = '';
  int _memoRows = 5, _projectLimit = 5;
  bool _memoHasMore = false;
  final _menuViewState = WorkspaceMenuViewState();
  bool get _menuVisible => desktopMenu.visible;
  set _menuVisible(bool value) => desktopMenu.setVisible(value);
  @override
  Note? _editing;
  List<Note> get _paragraphNotes => _notes.where((n) => n.project == null && n.paragraphs != null).toList();
  @override
  void _recordCaptured(ElementRecord record, List<ElementBinding> links) {
    if (_editing == null) {
      _notes.insert(0, Note(record.text)..bindings = links);
    } else {
      _editing!.content = record.text;
      _editing!.bindings = links;
    }
    _editing = null;
  }

  @override
  void _captureCompleted(ElementRecord record) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기록함에 담았어요. 다음 생각도 남겨보세요.')),
    );
    fillVoiceBody(record);
    _saveAndSync().catchError((Object e) { if (mounted) _captureError(e.toString()); });
    if (_desktopQuickMemo) { _focus.requestFocus(); } else { dismissKeyboard(); }
  }

  String? _storageError;
  Timer? _liveTimer, _contentTimer, _remoteDebounce;
  WorkspaceEvents? _events;
  bool _eventsConnected=false, _remotePending=false;
  void _remoteChanged() {
    _remotePending=true;
    _remoteDebounce ??= Timer(const Duration(milliseconds:200),_drainRemote);
  }
  Future<void> _drainRemote() async {
    _remoteDebounce=null;
    if(!mounted || !_remotePending)return;
    await _pollRemote();
    // Local retry only while a modal/editor/save temporarily prevents applying an event.
    if(mounted && _remotePending && WidgetsBinding.instance.lifecycleState!=AppLifecycleState.paused && WidgetsBinding.instance.lifecycleState!=AppLifecycleState.hidden)_remoteDebounce ??= Timer(const Duration(seconds:1),_drainRemote);
  }
  bool _checkingRemote=false, _applyingRemote=false;
  Future<void>? _contentSync;
  int _pollFailures=0;DateTime? _retryAfter;
  Future<void> _pollRemote() async {
    final storage=widget.storage;
    if(_retryAfter!=null && DateTime.now().isBefore(_retryAfter!))return;
    if(_checkingRemote || _contentTimer?.isActive==true || _contentSync!=null || !mounted || storage?.checkRemote==null || WidgetsBinding.instance.lifecycleState==AppLifecycleState.paused || WidgetsBinding.instance.lifecycleState==AppLifecycleState.hidden)return;
    _checkingRemote=true;
    try {
      // Keep the invalidation pending without querying while an editor/modal is open.
      if(storage!.editorResources.isNotEmpty || workspaceRouteObserver.current is PopupRoute)return;
      _remotePending=false;
      final changed=await storage.checkRemote!();
      _pollFailures=0;_retryAfter=null;
      if(changed && _contentTimer?.isActive!=true && _contentSync==null && storage.editorResources.isEmpty && mounted && workspaceRouteObserver.current is! PopupRoute){await _refreshForBrowse();}
      else if(changed){_remotePending=true;}
    } catch(e) { _remotePending=true;_pollFailures=(_pollFailures+1).clamp(1,4);_retryAfter=DateTime.now().add(Duration(seconds:(2<<_pollFailures).clamp(4,30)));if(mounted && _storageError==null)setState(()=>_storageError='서버 동기화를 확인하지 못했습니다. $e'); }
    finally{_checkingRemote=false;}
  }
  void _scheduleContentSync(){
    if(_applyingRemote || widget.storage?.syncContent==null)return;
    _contentTimer?.cancel();_contentTimer=Timer(const Duration(milliseconds:400),()async{
      try{await _syncContentNow();}catch(e){if(mounted)setState(()=>_storageError='변경을 기기에 보관했습니다. 서버 동기화에 실패했습니다. $e');}
    });
  }
  Future<void> _syncContentNow() async {
    while(_contentSync!=null){await _contentSync;}
    final request=widget.storage?.syncContent?.call();
    if(request==null)return;
    _contentSync=request;
    try{await request;}finally{_contentSync=null;}
  }
  bool _restoreBlocked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    openWorkspaceDocument = _openDocumentById;
    refreshWorkspaceForRead = _refreshForBrowse;
    saveWorkspaceContent = _saveAndSync;
    workspaceMemoAuthor=(id)=>overviewAuthor(widget.storage,'list:elements',id);
    if(widget.storage?.comments==null)memoCommentCounts.value={};
    voiceAudioRequest=widget.storage?.audioRequest;
    workspaceMapRequest=widget.storage?.audioRequest;
    memoCommentRequest=widget.storage?.comments;memoCommentsWritable=widget.storage?.commentsWritable??false;
    widget.storage?.applyServerSnapshot=_applyRemoteSnapshot;
    desktopMenu.visible = true;
    widget.storage?.hasUnsavedInput=()=>_draft.text.trim().isNotEmpty||_hasCapture;
    projectFolders.clear();
    paragraphFolders.clear();
    elementFolders.clear();
    hashtagFolders.clear();
    hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
    workspacePhotos.clear();
    pageGraphLayout = GraphLayout();
    memoBoxFolders.clear(); memoBoxFolderParents.clear();
    elements.addListener(_elementDeleted);
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
          note.paragraphs = null;
          note.bindings = [];
        }
      }
    } catch (_) {
      _restoreBlocked = true;
      _storageError = '브라우저 저장 데이터를 읽지 못했습니다. 기존 데이터는 보존되며 새 저장은 중단됩니다.';
    }
    ensureUnclassifiedBox();
    _events=widget.storage?.watchRemote?.call(_remoteChanged,(connected){_eventsConnected=connected;});
    _events?.resume();
    if(widget.storage?.checkRemote!=null)_liveTimer=Timer.periodic(const Duration(seconds:15),(_){if(!_eventsConnected)_pollRemote();});
    if (!_restoreBlocked) {
      _cleanupDeletedMedia().catchError((Object _) {});
      if (widget.storage?.canvasWritable == true) {
        unawaited(resumePendingVoiceTranscriptions());
      }
    }
  }

  void _elementRenamed(String oldText, String newText) {
    final records = {for (final record in elements.records.values) record.id: record.text};
    for (final note in _notes) {
      final paragraphs = note.project?.paragraphs ?? note.paragraphs;
      if (paragraphs != null) {
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
        note.bindings = List.of(elements.records[newText]?.inlineLinks ?? const <ElementBinding>[]);
      }
      final words = note.project?.words;
      if (words != null) {
        for (var i = 0; i < words.length; i++) {
          if (words[i] == oldText) words[i] = newText;
        }
      }
    }
  }

  int _seenDeletion = elements.deletionRevision;
  void _elementDeleted() {
    if(_applyingRemote)return;
    final deleted = _seenDeletion != elements.deletionRevision;
    _seenDeletion = elements.deletionRevision;
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

      }
    });
    if (deleted) {
      _persist().then((_) => widget.storage?.syncDeleted?.call()).catchError((Object e) {
        if (mounted) _captureError('삭제를 기기에 저장했습니다. 서버 동기화를 다시 시도해주세요. $e');
      });
    } else { _persist(); }
  }

  Future<void> _createFolder({bool tag = false, String? kind}) async {
    if (kind == 'box') { if (await createMemoFolder(context) && mounted) { setState(() {}); await _persist(); } return; }
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
        title: Text(tag ? '해시태그 폴더 만들기' : kind == 'paragraph' ? '문단 폴더 만들기' : kind == 'box' ? '메모상자 폴더 만들기' : kind == 'element' ? '생각 폴더 만들기' : '폴더 만들기'),
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
    _persist().then((_)=>widget.storage?.syncFolders?.call()).catchError((Object e){if(mounted)_captureError('폴더 변경 동기화에 실패했습니다. $e');});
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

  Future<void>? _persistPending;
  bool _persistAgain = false;
  Future<void> _persist() {
    _persistAgain = true;
    return _persistPending ??= Future<void>(() async {
      try {
        do {
          _persistAgain = false;
          await _persistOnce();
        } while (_persistAgain);
      } finally {
        _persistPending = null;
      }
    });
  }
  Future<void> _persistOnce() async {
    desktopMenu.refresh();
    if (widget.storage == null || _restoreBlocked) return;
    try {
      for (final note in _notes.where((n) => n.project != null)) { note.content = note.project!.content; }
      await widget.storage!.writeSnapshot(_notes);
      _scheduleContentSync();
      if (mounted && _storageError != null) setState(() => _storageError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _storageError = '브라우저 저장에 실패했습니다. 브라우저의 사이트 저장 공간 설정을 확인해주세요.',
        );
      }
    }
  }

  String get _mediaCleanupKey => widget.storage?.scoped('weaver.pendingMediaDeletion.v1') ?? 'weaver.pendingMediaDeletion.v1';
  Future<void> _cleanupDeletedMedia() async {
    final preferences = widget.storage?.preferences;
    if (preferences == null) return;
    final pending = preferences.getStringList(_mediaCleanupKey) ?? [];
    if (pending.isEmpty) return;
    final referenced = {for (final r in [...elements.records.values, ...elements.trash.values])
      ...[...r.photos.map((p) => p.id), ...r.recordings.map((c) => c.id)]};
    final failed = <String>[];
    for (final id in pending) {
      if (referenced.contains(id)) continue;
      try { await MediaStorage.delete(id,owner:widget.storage?.owner); } catch (_) { failed.add(id); }
    }
    await preferences.setStringList(_mediaCleanupKey, failed);
  }
  Future<void> _restoreThought(String id) async {
    final storage=widget.storage;
    if(storage==null || _restoreBlocked)throw StateError('저장소를 사용할 수 없습니다.');
    if(!storage.canvasWritable)throw StateError('읽기 전용 워크스페이스입니다.');
    await storage.writable();await storage.flush();
    final record=elements.trash[id];
    if(record!=null){
      final existing=elements.records[record.text];
      if(existing!=null && existing.id!=id)throw StateError('같은 내용의 생각이 이미 있습니다. 기존 생각의 내용을 수정한 후 다시 복구해주세요.');
      final deletedAt=record.deletedAt,folder=record.folder;
      record.deletedAt=null;
      if(record.folder!=null && !elementFolders.contains(record.folder))record.folder=null;
      elements.trash.remove(id);elements.records[record.text]=record;
      try{await storage.write(WorkspaceSnapshot.encode(_notes));}
      catch(_){elements.records.remove(record.text);record.deletedAt=deletedAt;record.folder=folder;elements.trash[id]=record;rethrow;}
      elements.refreshVisibility();
    }else if(!elements.records.values.any((r)=>r.id==id)){
      throw StateError('이미 영구 삭제되었거나 다른 기기에서 변경된 생각입니다.');
    }
    try{await _saveAndSync();if(!elements.records.values.any((r)=>r.id==id))throw StateError('서버의 최신 변경으로 복구가 적용되지 않았습니다. 자료를 확인해주세요.');}
    catch(e){if(!elements.records.values.any((r)=>r.id==id))rethrow;throw StateError('복구 내용은 이 기기에 보관했습니다. 서버 동기화를 다시 시도해주세요. $e');}
  }
  Future<void> _purgeThought(String id) async {
    final storage = widget.storage;
    if (storage == null || _restoreBlocked) throw StateError('Storage unavailable');
    final record = elements.trash[id];
    if (record == null) return;
    final files = {...(storage.preferences.getStringList(_mediaCleanupKey) ?? []),
      ...record.photos.map((p) => p.id), ...record.recordings.map((c) => c.id)};
    if (!await storage.preferences.setStringList(_mediaCleanupKey, files.toList())) throw StateError('Cleanup save failed');
    elements.trash.remove(id);
    if (![...elements.records.values, ...elements.trash.values].any((r) => r.text == record.text)) forgetWordColor(record.text);
    final boxes = [for (final box in memoBoxes) if (box.elementIds.remove(id)) box];
    try { await storage.write(WorkspaceSnapshot.encode(_notes)); }
    catch (_) { elements.trash[id] = record; for (final box in boxes) { box.elementIds.add(id); } rethrow; }
    elements.refreshVisibility();
    await _cleanupDeletedMedia();
    await storage.syncDeleted?.call();
  }
  Future<bool> _confirmTransfer(String title, String message) async => await showDialog<bool>(
    context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('계속'))])) == true;

  Future<void> _saveAndSync({String? resource}) async {
    await _persist();
    if (_storageError != null || _restoreBlocked) throw BackupFailure(_storageError ?? '로컬 저장을 확인해주세요.');
    if(resource==null){_contentTimer?.cancel();if(widget.storage?.syncContent!=null){await _syncContentNow();}else{await widget.storage?.syncNow?.call();}}
    else {await widget.storage?.syncResource?.call(resource);}
  }
  Future<void> _uploadBackup() async {await _saveAndSync();if(mounted)_captureError('저장되었습니다.');}
  Future<void> _downloadBackup() async {
    if(!await _confirmTransfer('서버 자료로 다시 불러올까요?', '현재 계정의 미동기화 수정을 서버 자료로 교체합니다. 다른 계정의 자료는 가져올 수 없습니다.'))return;
    await widget.storage?.pullNow?.call();
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모든 데이터를 초기화할까요?'),
        content: const Text('생각·문단·문서·폴더와 이 브라우저에 저장된 앱 데이터를 삭제합니다.'),
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
      final hasMedia = [...elements.records.values, ...elements.trash.values].any((r) => r.recordings.isNotEmpty || r.photos.isNotEmpty) ||
          (widget.storage?.preferences.getStringList(_mediaCleanupKey)?.isNotEmpty ?? false) ||
          widget.storage?.preferences.getString('${WorkspaceStorage.key}.beforeImport') != null;
      if (hasMedia) {
        for (final record in [...elements.records.values, ...elements.trash.values]) {
          for (final id in [...record.photos.map((p) => p.id), ...record.recordings.map((c) => c.id)]) { await MediaStorage.delete(id,owner:widget.storage?.owner); }
        }
      }
      await widget.storage?.clear();
      await widget.storage?.preferences.remove(_mediaCleanupKey);
      if (!mounted) return;
      setState(() {
        projectFolders.clear();
      paragraphFolders.clear();
      elementFolders.clear();
          hashtagFolders.clear();
        hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
    workspacePhotos.clear();
    pageGraphLayout = GraphLayout();
    memoBoxFolders.clear(); memoBoxFolderParents.clear();
        elements.clear();
        ensureUnclassifiedBox();
        _clearCapture();
        restoreWordColors({});
        _notes.clear();
        _draft.clear();
      _draftTags.clear();

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
    widget.storage?.applyServerSnapshot=null;
    _events?.dispose();_remoteDebounce?.cancel();_liveTimer?.cancel();_contentTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if(openWorkspaceDocument == _openDocumentById)openWorkspaceDocument=null;
    if(refreshWorkspaceForRead == _refreshForBrowse)refreshWorkspaceForRead=null;
    if(saveWorkspaceContent == _saveAndSync){saveWorkspaceContent=null;workspaceMemoAuthor=null;voiceAudioRequest=null;workspaceMapRequest=null;memoCommentRequest=null;memoCommentsWritable=false;}
    WidgetsBinding.instance.addPostFrameCallback((_) => desktopMenu.detach(this));
    elements.removeListener(_elementDeleted);
    elements.onRenamed = null;
    super.dispose();
  }

  void _moveParagraph(int index, String? folder) {
    setState(() => _paragraphNotes[index].folder = folder);
    _persist();
  }
  void _moveElement(int index, String? folder) {
    setState(() => elements.records[elements.words[index]]!.folder = folder);
    _persist();
  }

  List<String> get _allTags => {...elements.tags, ..._notes.expand((n) => n.project?.tags ?? <String>{}),
    ..._notes.where((n) => n.project == null && n.paragraphs != null).expand((n) => n.tags)}.toList()..sort();

  Future<void>? _browseRequest;
  bool _wasSuspended=false;
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed && _wasSuspended){
      _wasSuspended=false;_retryAfter=null;_events?.resume();_remoteChanged();
    }else if(state==AppLifecycleState.paused || state==AppLifecycleState.hidden){
      _wasSuspended=true;_events?.pause();_remoteDebounce?.cancel();_remoteDebounce=null;
    }
    // Inactive can mean an unfocused but visible browser window. Keep receiving
    // changes there; focus alone must never tear down/reload an overview tab.
  }
  Future<void> _refreshForBrowse() => _browseRequest ??= _performBrowseRefresh().whenComplete(() => _browseRequest = null);
  Future<void> _performBrowseRefresh() async {
    final storage = widget.storage;
    if (storage?.refreshNow == null || _restoreBlocked) return;
    final pending=_contentTimer?.isActive==true;
    await _contentSync;
    await _persist();
    _contentTimer?.cancel();
    if (_storageError != null) throw StateError(_storageError!);
    if(pending)await _syncContentNow();
    await storage!.refreshNow!();
    if(mounted)_applyRemoteSnapshot();
  }
  void _applyRemoteSnapshot({String? replaceResource}){
    final snapshot=WorkspaceSnapshot.decode(widget.storage!.read()!);
    final previous={for(final n in _notes)n.id:n};
    final oldBoxes={for(final b in memoBoxes)b.name:b};final oldLayout=pageGraphLayout;
    final notes=[for(final n in snapshot.notes) if(previous[n.id]?.project!=null && n.project!=null) (() {
      final old=previous[n.id]!,p=old.project!,next=n.project!;
      p.document=next.document;p.documentLinks=next.documentLinks;p.name=next.name;p.folder=next.folder;p.paragraphs=next.paragraphs;p.words..clear()..addAll(next.words);p.tags..clear()..addAll(next.tags);old.content=n.content;old.updatedAt=n.updatedAt;old.folder=n.folder;return old;
    })() else n];
    _applyingRemote=true;
    try{setState((){
      snapshot.apply();
      oldLayout.copyFrom(pageGraphLayout);pageGraphLayout=oldLayout;
      for(var i=0;i<memoBoxes.length;i++){
        final next=memoBoxes[i],old=oldBoxes[next.name];if(old==null)continue;
        old.color=next.color;old.folder=next.folder;if(!old.isUnclassified)old.elementIds..clear()..addAll(next.elementIds);old.layout.copyFrom(next.layout);memoBoxes[i]=old;
      }
      _notes..clear()..addAll(notes);elements.sources.clear();for(final n in notes){if(n.project!=null)elements.indexProject(n.project!);}
    });elements.refreshVisibility();desktopMenu.refresh();widget.storage!.liveChanges.value++;}
    finally{_applyingRemote=false;}
  }
  Future<void> _reloadResource(String id) async {
    await _persist();await widget.storage?.reloadResource?.call(id);
    if(mounted)_applyRemoteSnapshot(replaceResource:id);
  }
  Future<void> _renameMenuDocument(String id, String name) async {
    final storage = widget.storage;
    await storage?.writable();
    if (!mounted) return;
    final note = _notes.where((note) => note.project?.id == id).firstOrNull;
    if (note == null) return;
    final project = note.project!;
    final oldName = project.name;
    final oldDocument = project.document;
    final oldLinks = project.documentLinks;
    final oldUpdatedAt = note.updatedAt;

    // Keep the title used by the reader and the title in the menu in sync.
    final source = oldDocument ?? project.paragraphs.map((paragraph) => switch (paragraph.role) {
      ParagraphRole.title => '======${paragraph.text}======',
      ParagraphRole.subtitle => '=====${paragraph.text}=====',
      ParagraphRole.body => paragraph.text,
    }).join('\n\n');
    final code = codeMarkup.allMatches(source).toList();
    var start = 0;
    var end = 0;
    for (final match in RegExp(r'^======[^\r\n]*======(?=\r?$)', multiLine: true).allMatches(source)) {
      if (projectHeading.firstMatch(match.group(0)!)?.group(1)?.length != 6 ||
          code.any((block) => block.start < match.end && block.end > match.start)) continue;
      start = match.start;
      end = match.end;
      break;
    }
    final replacement = '======$name======${start == end && source.isNotEmpty ? '\n\n' : ''}';
    if (documentTitle(replacement) != name) {
      throw StateError('문서 제목으로 사용할 수 없는 형식입니다.');
    }
    final hadBase = storage?.documentSaveBases.containsKey(id) ?? false;
    final oldBase = storage?.documentSaveBases.remove(id);
    final delta = replacement.length - (end - start);
    setState(() {
      project.name = name;
      project.document = source.replaceRange(start, end, replacement);
      project.documentLinks = [
        for (final link in oldLinks)
          if (link.end <= start) link
          else if (link.start >= end) ElementBinding(link.id, link.start + delta, link.end + delta),
      ];
      note.updatedAt = DateTime.now();
      elements.indexProject(project);
    });
    try {
      await _saveAndSync(resource: id);
    } catch (_) {
      if (mounted && identical(note.project, project) && project.name == name) {
        setState(() {
          project.name = oldName;
          project.document = oldDocument;
          project.documentLinks = oldLinks;
          note.updatedAt = oldUpdatedAt;
          elements.indexProject(project);
        });
        if (hadBase) storage?.documentSaveBases[id] = oldBase;
        await _persist();
      }
      rethrow;
    }
  }

  Future<void> _renameMenuContainer(String kind, String oldName, String newName) async {
    final storage = widget.storage;
    await storage?.writable();
    if (!mounted) return;
    if (kind == 'box') {
      final box = memoBoxes.where((box) => box.name == oldName && !box.isUnclassified).firstOrNull;
      if (box == null) return;
      if (newName == '미분류' || memoBoxes.any((box) => box.name == newName)) {
        throw StateError('이미 사용 중인 상자 이름입니다.');
      }
      setState(() {
        final bounds = pageGraphLayout.blockLayout.containerBounds;
        final rect = bounds.remove('box:$oldName');
        if (rect != null) bounds['box:$newName'] = rect;
        box.name = newName;
      });
    } else {
      final folders = switch (kind) {
        'boxFolder' => memoBoxFolders,
        'projectFolder' => projectFolders,
        'paragraphFolder' => paragraphFolders,
        _ => elementFolders,
      };
      final index = folders.indexOf(oldName);
      if (index < 0) return;
      if (folders.contains(newName)) throw StateError('이미 사용 중인 폴더 이름입니다.');
      setState(() {
        folders[index] = newName;
        switch (kind) {
          case 'boxFolder':
            final parent = memoBoxFolderParents.remove(oldName);
            memoBoxFolderParents.updateAll((_, value) => value == oldName ? newName : value);
            if (parent != null) memoBoxFolderParents[newName] = parent;
            for (final box in memoBoxes) {
              if (box.folder == oldName) box.folder = newName;
            }
            for (final layout in [pageGraphLayout, pageGraphLayout.blockLayout]) {
              final position = layout.folderPositions.remove(oldName);
              if (position != null) layout.folderPositions[newName] = position;
              final rect = layout.containerBounds.remove('folder:$oldName');
              if (rect != null) layout.containerBounds['folder:$newName'] = rect;
            }
          case 'projectFolder':
            for (final note in _notes) {
              if (note.project?.folder == oldName) note.project!.folder = newName;
            }
          case 'paragraphFolder':
            for (final note in _paragraphNotes) {
              if (note.folder == oldName) note.folder = newName;
            }
          case 'elementFolder':
            for (final thought in elements.records.values) {
              if (thought.folder == oldName) thought.folder = newName;
            }
        }
      });
    }
    await _persist();
    if (_storageError != null || _restoreBlocked) {
      throw StateError(_storageError ?? '로컬 저장을 확인해주세요.');
    }
    if (kind == 'box' || kind == 'boxFolder') {
      await storage?.syncContent?.call();
      await storage?.syncCanvas?.call();
    } else {
      await storage?.syncFolders?.call();
    }
  }

  Future<void> _deleteMenuDocument(String id) async {
    final storage = widget.storage;
    await storage?.writable();
    if (!mounted) return;
    final index = _notes.indexWhere((note) => note.project?.id == id);
    if (index < 0) return;
    final note = _notes[index];
    setState(() {
      _notes.removeAt(index);
      elements.sources.remove(note.project);
    });
    await _persist();
    if (_storageError != null) {
      if (mounted) setState(() {
        _notes.insert(index.clamp(0, _notes.length), note);
        elements.indexProject(note.project!);
      });
      desktopMenu.refresh();
      throw StateError(_storageError!);
    }
    await storage?.writeDocumentDraft(id, null);
    await storage?.syncDeleted?.call();
  }

  Future<void> _deleteMenuBox(String name, ContainerDeletion choice) async {
    final storage = widget.storage;
    await storage?.writable();
    if (!mounted) return;
    final box = memoBoxes.where((box) => !box.isUnclassified && box.name == name).firstOrNull;
    if (box == null) return;
    final ids = box.elementIds.toSet();
    setState(() {
      removeMemoBoxesKeepingThoughts({name});
      pageGraphLayout.blockLayout.containerBounds.remove('box:$name');
      if (choice == ContainerDeletion.withThoughts) {
        elements.removeAll(ids.map((id) => elements.byId(id)?.text).nonNulls.toList());
      }
    });
    await _persist();
    if (_storageError != null) throw StateError(_storageError!);
    await storage?.syncFolders?.call();
  }

  Future<void> _deleteMenuBoxFolder(String folder, ContainerDeletion choice) async {
    final storage = widget.storage;
    await storage?.writable();
    if (!mounted || !memoBoxFolders.contains(folder)) return;
    setState(() {
      if (choice == ContainerDeletion.containerOnly) {
        removeMemoFolderKeepingContents(folder);
        pageGraphLayout.folderPositions.remove(folder);
        pageGraphLayout.blockLayout.containerBounds.remove('folder:$folder');
        return;
      }
      final subtree = memoBoxFolders.where((name) => memoFolderContains(folder, name)).toList()
        ..sort((a, b) => memoFolderDepth(b).compareTo(memoFolderDepth(a)));
      final names = subtree.toSet();
      final boxes = memoBoxes.where((box) => !box.isUnclassified && names.contains(box.folder)).toList();
      final ids = boxes.expand((box) => box.elementIds).toSet();
      removeMemoBoxesKeepingThoughts(boxes.map((box) => box.name).toSet());
      final bounds = pageGraphLayout.blockLayout.containerBounds;
      for (final box in boxes) {
        bounds.remove('box:${box.name}');
      }
      for (final name in subtree) {
        bounds.remove('folder:$name');
        removeMemoFolderKeepingContents(name);
        pageGraphLayout.folderPositions.remove(name);
      }
      elements.removeAll(ids.map((id) => elements.byId(id)?.text).nonNulls.toList());
    });
    await _persist();
    if (_storageError != null) throw StateError(_storageError!);
    await storage?.syncFolders?.call();
  }

  Future<void> _deleteBoxes(Set<String> names) async {
    final boxes = memoBoxes.where((b) => !b.isUnclassified && names.contains(b.name)).toList();
    final ids = boxes.expand((b) => b.elementIds).toSet();
    final records = [...elements.records.values, ...elements.trash.values].where((r) => ids.contains(r.id)).toList();
    final texts = records.map((r) => r.text).toSet();
    final storage = widget.storage;
    if (storage != null) {
      await storage.writable();
      final pending = {...(storage.preferences.getStringList(_mediaCleanupKey) ?? []), for (final r in records) ...[...r.photos.map((p) => p.id), ...r.recordings.map((v) => v.id)]};
      if (!await storage.preferences.setStringList(_mediaCleanupKey, pending.toList())) throw StateError('첨부 삭제 예약에 실패했습니다.');
    }
    final before = WorkspaceSnapshot.encode(_notes);
    try {
      elements.records.removeWhere((_, r) => ids.contains(r.id)); elements.trash.removeWhere((id, _) => ids.contains(id));
      for (final text in texts) { if (![...elements.records.values, ...elements.trash.values].any((r) => r.text == text)) forgetWordColor(text); }
      _notes.removeWhere((n) => n.project == null && texts.contains(n.content));
      for (final n in _notes) { n.project?.words.removeWhere(texts.contains); }
      memoBoxes.removeWhere((b) => boxes.contains(b));
      for (final b in memoBoxes) { if (!b.isUnclassified) b.elementIds.removeAll(ids); }
      await _persist(); if (_storageError != null) throw StateError(_storageError!);
    } catch (_) { final snapshot = WorkspaceSnapshot.decode(before); snapshot.apply(); _notes..clear()..addAll(snapshot.notes); rethrow; }
    elements.refreshVisibility();
    await storage?.syncDeleted?.call(); await _cleanupDeletedMedia();
    if (mounted) setState(() {});
  }
  Future<void> _deleteFolder(String kind, String folder) async {
    final before = WorkspaceSnapshot.encode(_notes);
    await widget.storage?.writable();
    try {
    if (kind == 'project') {
      projectFolders.remove(folder); for (final n in _notes) { if (n.project?.folder == folder) n.project!.folder = null; }
    } else if (kind == 'paragraph') {
      paragraphFolders.remove(folder); for (final n in _paragraphNotes) { if (n.folder == folder) n.folder = null; }
    } else if (kind == 'element') {
      elementFolders.remove(folder); for (final r in elements.records.values) { if (r.folder == folder) r.folder = null; }
    } else if (kind == 'tag') {
      hashtagFolders.remove(folder); hashtagFolderAssignments.removeWhere((_, value) => value == folder);
    }
    await _persist(); if (_storageError != null) throw StateError(_storageError!);
    } catch (_) { final snapshot = WorkspaceSnapshot.decode(before); snapshot.apply(); _notes..clear()..addAll(snapshot.notes); rethrow; }
    await widget.storage?.syncFolders?.call();
    elements.refreshVisibility(); if (mounted) setState(() {});
  }
  Future<void> _allThoughts([MemoBox? box, ThoughtView? view]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AllThoughtsPage(notes: _notes, onLayoutChanged: _persistLayouts, onChanged: _persist, onSave:_saveAndSync, initialBox: box, initialView: view, storage:widget.storage, onDocument:_showProject, onCreateDocument:_createProject, onRefresh:_refreshForBrowse, onReloadResource:_reloadResource, onDeleteBoxes:_deleteBoxes)));
    if (mounted) setState(() {});
  }

  bool _openingDocumentEditor = false;
  Future<void> _createProject() async {
    if (_openingDocumentEditor) return;
    _openingDocumentEditor = true;
    try {
      if (!await loadScreen(context, document_editor.loadLibrary) || !mounted) return;
      await _createProjectInEditor();
    } finally {
      _openingDocumentEditor = false;
    }
  }

  Future<void> _createProjectInEditor() async {
    final project = await Navigator.push<WritingProject>(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopMenuFrame(child: document_editor.ProjectDocumentEditor(storage:widget.storage,projects: _notes.map((n) => n.project).whereType<WritingProject>().toList(), onChanged: _persist)),
      ),
    );
    if (project == null || !mounted) return;
    final note = Note(project.content)
      ..project = project
      ..paragraphs = project.paragraphs;
    setState(() => _notes.insert(0, note));
    final newDraft=widget.storage?.documentDraft('new-document');
    if(newDraft!=null)await widget.storage!.writeDocumentDraft(project.id,newDraft);
    widget.storage?.documentSaveBases[project.id]=null;
    try{await _saveAndSync(resource:project.id);await widget.storage?.writeDocumentDraft(project.id,null);await widget.storage?.writeDocumentDraft('new-document',null);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('문서를 로컬에 보관했습니다. 서버에 저장하지 못했습니다. $e')));await _showProject(note);return;}
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('저장되었습니다.')));
    await _showProject(note);
  }

  Future<void> _openDocumentById(String id) async {
    final note=_notes.where((n)=>n.project?.id==id).firstOrNull;
    if(note!=null && mounted)await _showProject(note);
  }

  Future<void> _showProject(Note note) async {
    if (!mounted) return;
    final current = _notes.where((n) => n.id == note.id).firstOrNull;
    if (current == null) { _captureError('다른 기기에서 삭제된 문서입니다.'); return; }
    note = current;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProjectPage(project: note.project!, onOpenRefresh: _refreshForBrowse, projects: _notes.map((n) => n.project).whereType<WritingProject>().toList(), onChanged: ()async{if(note.content!=note.project!.content)note.updatedAt=DateTime.now();note.content=note.project!.content;await _persist();}, onSave: () => _saveAndSync(resource:note.project!.id), onHistory:widget.storage?.openHistory, onLease:widget.storage?.documentLease, storage:widget.storage, onReload:()=>_reloadResource(note.project!.id)),
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
    if (_draft.text.isNotEmpty || _voiceDraft != null || _photoDrafts.isNotEmpty || _draftLocation != null) {
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
      _clearCapture();
      _draftLocation = elements.records[note.content.trim()]?.location;
      _draftImportant = elements.records[note.content.trim()]?.important ?? false;
      _editing = note;
      final tags = elements.records[note.content.trim()]?.tags ?? <String>{};
      _draftTags.clear();
      _draft.loadDocument([note.content, ...tags.map((tag) => '#$tag')].join(' '), note.bindings);
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
        viewState: _menuViewState,
        projects: projects.map((n) => n.title).toList(),
        projectIds: projects.map((n) => n.project!.id).toList(),
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
        onRename: (widget.storage?.canvasWritable ?? true) ? _renameMenuContainer : null,
        onRenameDocument: (widget.storage?.canvasWritable ?? true) ? _renameMenuDocument : null,
        onDeleteFolder: _deleteFolder,
        onDeleteDocument: (widget.storage?.canvasWritable ?? true) ? _deleteMenuDocument : null,
        onDeleteBox: (widget.storage?.canvasWritable ?? true) ? _deleteMenuBox : null,
        onDeleteBoxFolder: (widget.storage?.canvasWritable ?? true) ? _deleteMenuBoxFolder : null,
        folders: projectFolders,
        projectFolderNames: projects.map((n) => n.project!.folder).toList(),
      ),
    );
    await _selectMenu(choice, projects, tags);
    if (mounted &&
        (choice == WorkspaceMenu.refresh || choice == WorkspaceMenu.createFolder ||
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
    if (choice == WorkspaceMenu.home) { await navigateHome(context); if (mounted && !Navigator.of(context).canPop()) { try { await _refreshForBrowse(); } catch (e) { if (mounted) _captureError('서버 변경을 확인하지 못했습니다. $e'); } } return; }
    if (choice == WorkspaceMenu.settings) { await showThoughtSettings(context, widget.storage?.preferences, onSyncReview: widget.storage?.openSyncReview, onUpload: _uploadBackup, onDownload: _downloadBackup, onReset: _reset, offline:widget.storage?.offlineMode??false,onExportFile:widget.storage?.exportFile,onImportFile:widget.storage?.importFile,onAdmin:widget.storage?.openAdmin, onPlan:widget.storage?.openPlan, onWorkspaces:widget.storage?.openWorkspaces, workspaceName:widget.storage?.workspaceName, onSignIn: () async {
      if (_draft.text.trim().isNotEmpty || _hasCapture) throw const BackupFailure('작성 중인 메모를 저장한 뒤 로그인해주세요.');
      if (_captureSaving || _locationBusy || _photoBusy) throw const BackupFailure('메모와 첨부 처리 완료 후 다시 시도해주세요.');
      await _persist();
      if (_storageError != null || _restoreBlocked) throw const BackupFailure('로컬 저장 상태를 확인한 뒤 로그인해주세요.');
      if (mounted) await GoogleAuthScope.maybeOf(context)?.leaveGuest();
    }); return; }
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
    if (choice == WorkspaceMenu.trash) {
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => TrashPage(onDelete: _purgeThought,onRestore:widget.storage?.canvasWritable==false?null:_restoreThought)));
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


  Widget _homeSectionTitle(String title, {int? count}) => Row(children: [
    Text(title, style: Theme.of(context).textTheme.titleMedium),
    if (count != null) ...[
      const SizedBox(width: 8),
      Text('$count', style: TextStyle(color: colors.primary)),
    ],
  ]);

  List<ElementRecord> _orderedNotices() => elements.records.values
      .where((thought) => thought.noticeBoardAt != null)
      .toList()
    ..sort((a, b) {
      final byOrder = (a.noticeBoardOrder ?? -1).compareTo(b.noticeBoardOrder ?? -1);
      if (byOrder != 0) return byOrder;
      final byDate = b.noticeBoardAt!.compareTo(a.noticeBoardAt!);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });

  Future<void> _reorderNotices(List<ElementRecord> visible, int from, int to) async {
    if (from == to || _restoreBlocked) return;
    final visibleIds = visible.map((thought) => thought.id).toList();
    try {
      await widget.storage?.writable();
      if (!mounted) return;
      final ordered = _orderedNotices();
      final current = ordered.where(canBrowseThought).take(noticeBoardLimit);
      if (!listEquals(visibleIds, current.map((thought) => thought.id).toList())) return;
      final visibleSet = visibleIds.toSet();
      final reordered = current.toList();
      reordered.insert(to, reordered.removeAt(from));
      var next = 0;
      setState(() {
        for (var i = 0; i < ordered.length; i++) {
          if (visibleSet.contains(ordered[i].id)) ordered[i] = reordered[next++];
          ordered[i].noticeBoardOrder = i;
        }
      });
      await _saveAndSync();
    } catch (error) {
      if (mounted) _captureError('알림판 순서를 저장하지 못했습니다. $error');
    }
  }

  Widget _noticeBoard({required bool mobile}) {
    final visible = _orderedNotices().where(canBrowseThought).take(noticeBoardLimit).toList();
    final canReorder = visible.length > 1 && !_restoreBlocked &&
        (widget.storage?.canvasWritable ?? true);
    final divider = Divider(
      height: 18,
      thickness: 1,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      divider,
      _homeSectionTitle('알림판', count: visible.length),
      const SizedBox(height: 6),
      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('지금은 알릴 만한 게 없습니다.', style: TextStyle(color: colors.onSurfaceVariant)),
        )
      else
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: visible.length,
          onReorderItem: (from, to) => _reorderNotices(visible, from, to),
          itemBuilder: (context, index) {
            final thought = visible[index];
            const icon = Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.drag_handle, size: 18),
            );
            return ListTile(
              key: ValueKey('notice-board-${thought.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              minTileHeight: 38,
              leading: canReorder
                ? ReorderableDragStartListener(
                    index: index,
                    child: const Tooltip(message: '순서 바꾸기', child: icon),
                  )
                : icon,
              title: Text(thought.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => showElementMetadata(context, thought.text),
            );
          },
        ),
      if (mobile) divider,
    ]);
  }

  Widget _composerWithNoticeBoard(double maxHeight, {bool mobile = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _composer(maxHeight),
      const SizedBox(height: 4),
      _noticeBoard(mobile: mobile),
    ],
  );

  Widget _list() {
    final visible = _notes
        .where((n) => n.content.toLowerCase().contains(_query.toLowerCase()) || n.title.toLowerCase().contains(_query.toLowerCase()) || n.tags.any((t) => t.contains(_query.toLowerCase().replaceFirst('#', ''))))
        .toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final query = _query.toLowerCase().replaceFirst('#', '');
    final records = elements.records.values.where((record) => canBrowseThought(record) &&
      (record.indexLabel.toLowerCase().contains(_query.toLowerCase()) || record.text.toLowerCase().contains(_query.toLowerCase()) || record.tags.any((tag) => tag.contains(query))))
      .toList()..sort(compareThoughtPriority);
    final projects = visible.where((note) => note.project != null).toList();
    final moreStyle = TextButton.styleFrom(textStyle: const TextStyle(fontSize: 11),
      minimumSize: const Size(0, 24), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final badges = [for (final record in records) WordBadge(
      word: record.text, query: _query, fullText: true,
      onLongPress: () => showElementMetadata(context, record.text),
      onTap: () => showElementMetadata(context, record.text))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _homeSectionTitle('모아둔 생각', count: _notes.length),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('note-search'),
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
          onChanged: (value) => setState(() {
            _query = value; _memoRows = 5; _projectLimit = 5; _memoHasMore = false;
          }),
          decoration: const InputDecoration(
            hintText: '메모에서 찾기',
            prefixIcon: Icon(Icons.search, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
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
        if (_query.isEmpty) ClipRect(child: PackedBadges(
          key: const ValueKey('recent-memo-badges'), maxRows: _memoRows, alwaysVisibleCount:records.where((r)=>r.important).length,
          onOverflowChanged: (overflow) { if (mounted && _memoHasMore != overflow) setState(() => _memoHasMore = overflow); },
          children: badges))
        else PackedBadges(children: badges),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_query.isEmpty && _memoHasMore) TextButton(key: const ValueKey('thoughts-more'), style: moreStyle,
            onPressed: () => setState(() => _memoRows += 5), child: const Text('+더보기')),
          TextButton(key: const ValueKey('thoughts-all'), style: moreStyle,
            onPressed: () => _allThoughts(null, ThoughtView.page), child: const Text('모두보기')),
        ]),
        if (projects.isNotEmpty) ...[
          Divider(key: const ValueKey('main-project-divider'),
            height: 18, thickness: 1, color: colors.outlineVariant.withValues(alpha: .45)),
          Padding(padding: const EdgeInsets.only(bottom: 6),
            child: _homeSectionTitle('문서', count: projects.length)),
          for (final note in projects.take(_projectLimit))
            _recentNoteCard(note),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (projects.length > _projectLimit)
              TextButton(key: const ValueKey('projects-more'), style: moreStyle,
                onPressed: () => setState(() => _projectLimit += 5),
                child: const Text('+더보기')),
            TextButton(key: const ValueKey('projects-all'), style: moreStyle,
              onPressed: () => _allThoughts(null, ThoughtView.documents),
              child: const Text('모두보기')),
          ]),
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
                '${note.createdAt.month}월 ${note.createdAt.day}일 · ${note.project != null ? '문서' : '문단'}${note.tags.isEmpty ? '' : ' · ${note.tags.map((t) => '#$t').join(' ')}'}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _open(note),
            ),
          );

  Widget _desktopSidebar(BuildContext context) => SafeArea(top: false,
              child: WorkspaceMenu(
                viewState: _menuViewState,
                embedded: true,
                onFloat: () { setState(() => _menuVisible = false); _menu(); },
                onHide: () => setState(() => _menuVisible = false),
                projects: _notes
                    .where((n) => n.project != null)
                    .map((n) => n.title)
                    .toList(),
                projectIds: _notes.where((n) => n.project != null).map((n) => n.project!.id).toList(),
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
        onRename: (widget.storage?.canvasWritable ?? true) ? _renameMenuContainer : null,
        onRenameDocument: (widget.storage?.canvasWritable ?? true) ? _renameMenuDocument : null,
        onDeleteFolder: _deleteFolder,
        onDeleteDocument: (widget.storage?.canvasWritable ?? true) ? _deleteMenuDocument : null,
        onDeleteBox: (widget.storage?.canvasWritable ?? true) ? _deleteMenuBox : null,
        onDeleteBoxFolder: (widget.storage?.canvasWritable ?? true) ? _deleteMenuBoxFolder : null,
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
      appBar: MainAppBar(
        auth:GoogleAuthScope.maybeOf(context),
        onNotification:widget.storage?.openNotification,
        onTitle:MediaQuery.sizeOf(context).width >= 1000 ? () => navigateHome(context) : null,
        leading: AnimatedBuilder(animation: desktopMenu, builder: (context, _) =>
          MediaQuery.sizeOf(context).width >= 1000 && _menuVisible
            ? Padding(padding: const EdgeInsets.all(14), child: Image.asset(
                'assets/branding/favicon.png', color: Theme.of(context).colorScheme.onSurface,
                semanticLabel: '위버'))
            : IconButton(tooltip: '메뉴 열기', onPressed: _menu,
                icon: const Icon(Icons.grid_view_rounded))),
      ),
      body: DesktopMenuBody(child: SizedBox(key: _bodyKey, child: Row(
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
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(onPressed: _allThoughts, icon: const Icon(Icons.bubble_chart_outlined, size: 18),
                              label: const Text('전체 보기')),
                            TextButton.icon(
                              onPressed: () => _allThoughts(ensureUnclassifiedBox()),
                              icon: const Icon(
                                Icons.inventory_2_outlined,
                                size: 18,
                              ),
                              label: const Text('미분류 정리하기'),
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
                                        child: RepaintBoundary(child: _list()),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(child: RepaintBoundary(child: _composerWithNoticeBoard(composerHeight))),
                                  ],
                                )
                              : Column(
                                  children: [
                                    RepaintBoundary(child: _composerWithNoticeBoard(composerHeight, mobile: true)),
                                    const SizedBox(height: 24),
                                    RepaintBoundary(child: _list()),
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
      ))),
    )));
  }
}

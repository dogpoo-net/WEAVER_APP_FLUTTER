import 'dart:async';
import 'label_links.dart';
import '../auth/google_auth.dart';
import '../sync/workspace_backup.dart';
import 'trash_page.dart';
import 'thought_settings.dart';
import '../auth/profile_page.dart';
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
import 'limited_rows_wrap.dart';
import 'caret_assist.dart';
import 'element_binding.dart';
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
import 'project_document_editor.dart';
import 'all_thoughts_page.dart';
import 'workspace_menu.dart';
import 'element_store.dart';

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

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  final _draft = LabelTextController();
  final _draftTags = <String>{};
  ThoughtLocation? _draftLocation;
  VoiceDraft? _voiceDraft;
  final _photoDrafts = <PhotoDraft>[];
  VoiceAttachment? _savedVoice;
  final _savedPhotos = <PhotoAttachment>[];
  bool _locationBusy = false, _captureSaving = false, _photoBusy = false;
  int _locationGeneration = 0;
  bool get _mobileCapture => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  void _clearCapture() {
    _locationGeneration++; _draftLocation = null; _locationBusy = false;
    _voiceDraft = null; _photoDrafts.clear(); _savedVoice = null; _savedPhotos.clear();
  }
  void _captureError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  Future<void> _toggleLocation(bool enabled) async {
    final generation = ++_locationGeneration;
    if (!enabled) { setState(() { _locationBusy = false; _draftLocation = null; }); return; }
    setState(() => _locationBusy = true);
    try {
      final location = await captureLocation();
      if (mounted && generation == _locationGeneration) setState(() => _draftLocation = location);
    } catch (error) {
      if (mounted && generation == _locationGeneration) _captureError(error is StateError ? error.message.toString() : '위치를 가져오지 못했습니다. 위치 권한과 기기 설정을 확인해주세요.');
    } finally {
      if (mounted && generation == _locationGeneration) setState(() => _locationBusy = false);
    }
  }
  Future<void> _recordVoice() async {
    dismissKeyboard();
    final draft = await showVoiceRecorder(context);
    if (draft != null && mounted) setState(() => _voiceDraft = draft);
  }
  Future<void> _pickPhotos() async {
    if (_photoBusy || _photoDrafts.length >= 5) return;
    setState(() => _photoBusy = true);
    try {
      final remaining = 5 - _photoDrafts.length;
      final picker = ImagePicker();
      final List<XFile> picked;
      if (remaining == 1) {
        final photo = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
        picked = photo == null ? [] : [photo];
      } else {
        picked = await picker.pickMultiImage(limit: remaining, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
      }
      final photos = <PhotoDraft>[];
      for (final photo in picked.take(remaining)) {
        if (await photo.length() > 10 * 1024 * 1024) { _captureError('사진 한 장은 10MB 이하로 선택해주세요.'); continue; }
        final bytes = await photo.readAsBytes();
        photos.add(PhotoDraft(bytes, photo.name));
      }
      if (mounted) setState(() => _photoDrafts.addAll(photos));
    } catch (_) { _captureError('사진을 가져오지 못했습니다. 사진 접근 권한을 확인해주세요.'); }
    finally { if (mounted) setState(() => _photoBusy = false); }
  }
  bool get _hasCapture => _voiceDraft != null || _photoDrafts.isNotEmpty || _draftLocation != null;
  Future<void> _saveCapture() async {
    if (_captureSaving || _locationBusy || _photoBusy) return;
    final text = parseTaggedInput(_draft.text).text;
    if (text.isEmpty && !_hasCapture) { _captureError('생각 내용이나 첨부를 추가해주세요.'); return; }
    if (_voiceDraft == null && _photoDrafts.isEmpty) { _save(); return; }
    if (widget.storage == null || _restoreBlocked) { _captureError('저장소를 사용할 수 없습니다. 메모와 첨부는 유지됩니다.'); return; }
    final existing = _editing == null ? elements.records[text] : elements.records[_editing!.content.trim()];
    if ((existing?.photos.length ?? 0) + _photoDrafts.length > 5) {
      _captureError('같은 내용의 생각에 이미 첨부된 사진을 포함해 최대 5장까지 저장할 수 있습니다.'); return;
    }
    setState(() => _captureSaving = true);
    final written = <String>[];
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final voice = _voiceDraft;
      if (voice != null) {
        final id = 'voice-$stamp';
        written.add(id); await MediaStorage.write(id, voice.bytes,owner:widget.storage?.owner);
        _savedVoice = VoiceAttachment(id, voice.durationMs);
      }
      for (var i = 0; i < _photoDrafts.length; i++) {
        final photo = _photoDrafts[i], id = 'photo-$stamp-$i';
        written.add(id); await MediaStorage.write(id, photo.bytes,owner:widget.storage?.owner);
        _savedPhotos.add(PhotoAttachment(id, photo.name));
      }
      if (!mounted) throw StateError('Composer closed');
      if (!_save()) throw StateError('Memo not saved');
    } catch (_) {
      for (final id in written) { try { await MediaStorage.delete(id,owner:widget.storage?.owner); } catch (_) {} }
      _savedVoice = null; _savedPhotos.clear();
      _captureError('첨부 저장에 실패했습니다. 작성한 메모와 첨부는 유지됩니다. 저장 공간을 확인해주세요.');
    } finally { if (mounted) setState(() => _captureSaving = false); }
  }
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
  TextEditingValue? _assistInputBefore, _assistCompleted, _lastComposingValue;
  String? _assistComposingEcho;
  DateTime? _assistSubmitUntil;
  DateTime? _newlineEchoUntil;
  bool _platformEnterQueued = false;
  String? _enterEchoText, _enterEchoSyllable;
  DateTime? _enterEchoUntil, _explicitNewlineUntil;
  bool get _desktopQuickMemo => defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux;
  Note? _editing;
  String? _storageError;
  Timer? _liveTimer, _contentTimer;
  bool _checkingRemote=false, _applyingRemote=false;
  Future<void>? _contentSync;
  int _pollFailures=0;DateTime? _retryAfter;
  Future<void> _pollRemote() async {
    final storage=widget.storage;
    if(_retryAfter!=null && DateTime.now().isBefore(_retryAfter!))return;
    if(_checkingRemote || _contentTimer?.isActive==true || _contentSync!=null || !mounted || storage?.checkRemote==null || WidgetsBinding.instance.lifecycleState==AppLifecycleState.paused || WidgetsBinding.instance.lifecycleState==AppLifecycleState.hidden || WidgetsBinding.instance.lifecycleState==AppLifecycleState.inactive)return;
    _checkingRemote=true;
    try {
      final changed=await storage!.checkRemote!();
      _pollFailures=0;_retryAfter=null;
      if(changed && _contentTimer?.isActive!=true && _contentSync==null && storage.editorResources.isEmpty && mounted && workspaceRouteObserver.current is! PopupRoute)await _refreshForBrowse();
    } catch(e) { _pollFailures=(_pollFailures+1).clamp(1,4);_retryAfter=DateTime.now().add(Duration(seconds:(2<<_pollFailures).clamp(4,30)));if(mounted && _storageError==null)setState(()=>_storageError='서버 동기화를 확인하지 못했습니다. $e'); }
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
    widget.storage?.applyServerSnapshot=_applyRemoteSnapshot;
    desktopMenu.visible = true;
    _draft.addListener(_imeUpdated);
    widget.storage?.hasUnsavedInput=()=>_draft.text.trim().isNotEmpty||_hasCapture;
    projectFolders.clear();
    paragraphFolders.clear();
    elementFolders.clear();
    hiddenSearchTags.clear();
    hashtagFolders.clear();
    hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
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
    if(widget.storage?.checkRemote!=null)_liveTimer=Timer.periodic(const Duration(seconds:3),(_)=>_pollRemote());
    if (!_restoreBlocked) _cleanupDeletedMedia().catchError((Object _) {});
  }

  void _elementRenamed(String oldText, String newText) {
    for (final note in _notes) {
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

  Future<void> _persist() async {
    desktopMenu.refresh();
    if (widget.storage == null || _restoreBlocked) return;
    try {
      for (final note in _notes.where((n) => n.project != null)) { note.content = note.project!.content; }
      final workspaceSave = widget.storage!.write(WorkspaceSnapshot.encode(_notes));
      final layoutSave = _persistLayouts();
      await workspaceSave;
      await layoutSave;
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
      hiddenSearchTags.clear();
        hashtagFolders.clear();
        hashtagFolderAssignments.clear();
    hashtagColors.clear();
    memoBoxes.clear();
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
    _liveTimer?.cancel();_contentTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if(openWorkspaceDocument == _openDocumentById)openWorkspaceDocument=null;
    if(refreshWorkspaceForRead == _refreshForBrowse)refreshWorkspaceForRead=null;
    if(saveWorkspaceContent == _saveAndSync)saveWorkspaceContent=null;
    WidgetsBinding.instance.addPostFrameCallback((_) => desktopMenu.detach(this));
    elements.removeListener(_elementDeleted);
    elements.onRenamed = null;
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitQuickMemo() {
    if (_assistSubmitUntil != null && DateTime.now().isBefore(_assistSubmitUntil!)) return;
    if (_pendingImeNewline || (_explicitNewlineUntil != null && DateTime.now().isBefore(_explicitNewlineUntil!))) return;
    if (_quickAssistKey.currentState?.acceptVisibleCandidate() == true) return;
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
      final echo = _assistComposingEcho;
      final caret = completedAssist.selection.extentOffset;
      if (echo != null && caret >= 0 && caret <= completedAssist.text.length) {
        final echoed = completedAssist.text.replaceRange(caret, caret, echo);
        if (value.text == echoed || value.text == '$echoed\n' || value.text == '$echoed\r\n') {
          return completedAssist;
        }
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
    if (oldValue.text.isEmpty && _enterEchoUntil != null && now.isBefore(_enterEchoUntil!) &&
        (value.text == _enterEchoText || (_enterEchoSyllable != null && value.text == _enterEchoSyllable))) { return oldValue; }
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
    final value = _draft.value;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      _lastComposingValue = value;
    } else if (_lastComposingValue?.text != value.text) {
      _lastComposingValue = null;
    }
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
        _enterEchoUntil = null; _enterEchoSyllable = null;
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
        _enterEchoSyllable = value.composing.textInside(value.text);
        final committed = value.copyWith(composing: TextRange.empty);
        _pendingImeSave = false;
        _focus.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        _draft.value = committed;
        _submitQuickMemo();
        return KeyEventResult.handled;
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

  Future<void> _acceptQuickAssist(FutureOr<void> Function() action) async {
    final before = _draft.value;
    final composing = _lastComposingValue;
    _assistComposingEcho = composing != null && composing.text == before.text
        ? composing.composing.textInside(composing.text) : null;
    final result = action();
    _pendingImeSave = false;
    _assistInputBefore = before; _assistCompleted = _draft.value;
    _assistSubmitUntil = DateTime.now().add(const Duration(milliseconds: 500));
    if (result is Future) {
      await result;
      if (!mounted) return;
      _assistCompleted = _draft.value;
      _assistSubmitUntil = DateTime.now().add(const Duration(milliseconds: 500));
    }
  }

  Future<void> _insertQuickElement(String word) async {
    await insertAssistedLink(context, _draft, word); if (mounted) { setState(() {}); _focus.requestFocus(); }
  }

  void _insertQuickTag(String tag) {
    // Close the native IME connection before removing its composing token.
    // Otherwise the platform can insert the final syllable again after removal.
    if (_draft.value.composing.isValid && !_draft.value.composing.isCollapsed) {
      final committed = _draft.value.copyWith(composing: TextRange.empty);
      _focus.unfocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      _draft.value = committed;
    }
    final token = tagPrefix(_draft.value);
    if (!token.startsWith('#')) return;
    final start = _draft.selection.start - token.length;
    setState(() {
      final replacement = '#$tag ';
      _draft.value = TextEditingValue(text: _draft.text.replaceRange(start, _draft.selection.end, replacement),
        selection: TextSelection.collapsed(offset: start + replacement.length));
    });
    _focus.requestFocus();
  }

  bool _save() {
    _pendingImeSave = false;
    if (_draft.text.trim().isEmpty && !_hasCapture) return false;
    final committed = _draft.value.copyWith(composing: TextRange.empty);
    if (_desktopQuickMemo) {
      _focus.unfocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      _draft.value = committed;
    }
    _draft.completeLinks();
    final cleaned = cleanLinkedInput(_draft);
    var body = cleaned.text;
    if (body.trim().isEmpty && _hasCapture) {
      final title = attachmentMemoText(DateTime.now(), photos: _photoDrafts.isNotEmpty, audio: _voiceDraft != null, location: _draftLocation != null);
      body = title;
    }
    if (body.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('태그와 함께 생각 내용을 입력해주세요.')));
      return false;
    }
    final tags = {..._draftTags, ...cleaned.tags};
    final input = body;
    final editing = _editing;
    ElementRecord record;
    if (editing != null) {
      final original = elements.records[editing.content.trim()];
      if (original == null) { _captureError('이미 삭제된 생각입니다.'); return false; }
      final error = elements.update(original.text, input, tags: tags, inlineLinks: cleaned.links);
      if (error != null) { _captureError(error); return false; }
      record = original;
    } else {
      record = elements.addLinked(input, cleaned.links, tags);
    }
    if (_draftLocation != null || _editing != null) record.location = _draftLocation;
    if (_savedVoice != null) record.recordings.add(_savedVoice!);
    record.photos.addAll(_savedPhotos);
    final links = List<ElementBinding>.of(cleaned.links);
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

      _clearCapture();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('기록함에 담았어요. 다음 생각도 남겨보세요.')));
    _saveAndSync().catchError((Object e) { if(mounted)_captureError(e.toString()); });
    if (_desktopQuickMemo) { _focus.requestFocus(); } else { dismissKeyboard(); }
    return true;
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

  List<String> get _allTags => {...hashtagColors.keys, ...elements.tags, ..._notes.expand((n) => n.project?.tags ?? <String>{}),
    ..._notes.where((n) => n.project == null && n.paragraphs != null).expand((n) => n.tags)}.toList()..sort();

  Future<void>? _browseRequest;
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && ModalRoute.of(context)?.isCurrent == true) {
      _refreshForBrowse().catchError((Object e) { if (mounted) _captureError('서버 변경을 확인하지 못했습니다. $e'); });
    }
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
    if (kind == 'box') {
      final removed = memoBoxFolders.where((f) => memoFolderContains(folder, f)).toSet();
      for (final b in memoBoxes) { if (removed.contains(b.folder)) b.folder = null; }
      memoBoxFolders.removeWhere(removed.contains); memoBoxFolderParents.removeWhere((key, value) => removed.contains(key) || removed.contains(value));
    } else if (kind == 'project') {
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
  Future<void> _allThoughts([MemoBox? box]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AllThoughtsPage(notes: _notes, onLayoutChanged: _persistLayouts, onChanged: _persist, onSave:_saveAndSync, initialBox: box, storage:widget.storage, onDocument:_showProject, onRefresh:_refreshForBrowse, onReloadResource:_reloadResource, onDeleteBoxes:_deleteBoxes)));
    if (mounted) setState(() {});
  }

  Future<void> _createProject() async {
    final project = await Navigator.push<WritingProject>(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopMenuFrame(child: ProjectDocumentEditor(projects: _notes.map((n) => n.project).whereType<WritingProject>().toList(), onChanged: _persist)),
      ),
    );
    if (project == null || !mounted) return;
    final note = Note(project.content)
      ..project = project
      ..paragraphs = project.paragraphs;
    setState(() => _notes.insert(0, note));
    await _saveAndSync(resource:project.id);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('저장되었습니다.')));
    await _showProject(note);
  }

  Future<void> _openDocumentById(String id) async {
    final note=_notes.where((n)=>n.project?.id==id).firstOrNull;
    if(note!=null && mounted)await _showProject(note);
  }

  Future<void> _showProject(Note note) async {
    try { await _refreshForBrowse(); } catch (e) { if (mounted) _captureError('서버 변경을 확인하지 못했습니다. $e'); }
    if (!mounted) return;
    final current = _notes.where((n) => n.id == note.id).firstOrNull;
    if (current == null) { _captureError('다른 기기에서 삭제된 문서입니다.'); return; }
    note = current;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProjectPage(project: note.project!, projects: _notes.map((n) => n.project).whereType<WritingProject>().toList(), onChanged: ()async{if(note.content!=note.project!.content)note.updatedAt=DateTime.now();note.content=note.project!.content;await _persist();}, onSave: () => _saveAndSync(resource:note.project!.id), onHistory:widget.storage?.openHistory, onLease:widget.storage?.documentLease, storage:widget.storage, onReload:()=>_reloadResource(note.project!.id)),
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
        onDeleteFolder: _deleteFolder,
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
    if (choice == WorkspaceMenu.home) { await navigateHome(context); if (mounted && !Navigator.of(context).canPop()) { try { await _refreshForBrowse(); } catch (e) { if (mounted) _captureError('서버 변경을 확인하지 못했습니다. $e'); } } return; }
    if (choice == WorkspaceMenu.settings) { await showThoughtSettings(context, widget.storage?.preferences, onUpload: _uploadBackup, onDownload: _downloadBackup, onReset: _reset, onInvite:widget.storage?.openSharing, onWorkspaces:widget.storage?.openWorkspaces, workspaceName:widget.storage?.workspaceName, onSignIn: () async {
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
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => TrashPage(onDelete: _purgeThought)));
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
              Expanded(child: Text(
                _editing == null ? '빠른 메모' : '메모 다듬기', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              )),
              if (_mobileCapture) ...[
                IconButton(key: const ValueKey('quick-location'),
                  tooltip: _locationBusy ? '위치 요청 취소' : _draftLocation == null ? '위치 기록' : '위치 기록 해제',
                  isSelected: _draftLocation != null,
                  style: IconButton.styleFrom(backgroundColor: _draftLocation != null ? colors.secondaryContainer : null),
                  visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 32, height: 32), padding: EdgeInsets.zero,
                  onPressed: _captureSaving ? null : () => _toggleLocation(!_locationBusy && _draftLocation == null),
                  selectedIcon: const Icon(Icons.location_on, size: 19),
                  icon: _locationBusy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.location_on_outlined, size: 19)),
                IconButton(tooltip: '음성 메모', visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 32), padding: EdgeInsets.zero,
                  onPressed: _captureSaving || _photoBusy ? null : _recordVoice, icon: const Icon(Icons.mic_none, size: 19)),
                PopupMenuButton<String>(key: const ValueKey('quick-photo-menu'), tooltip: '사진 첨부 (최대 5장)',
                  enabled: !_captureSaving && !_photoBusy && _photoDrafts.length < 5,
                  position: PopupMenuPosition.under, padding: EdgeInsets.zero,
                  iconSize: 19, icon: const Icon(Icons.add_photo_alternate_outlined),
                  onSelected: (_) => _pickPhotos(),
                  itemBuilder: (_) => [PopupMenuItem(value: 'gallery', child: Text('사진 선택 (${5 - _photoDrafts.length}장까지)'))]),
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
            child: CaretAssist(useThoughtLabels: true, showShortcutHint: true, key: _quickAssistKey, controller: _draft, focus: _focus, words: labelAssistTargets(), showWhenEmpty: false,
              mobileViewportKey: _bodyKey,
              tags: {..._allTags, ..._draftTags}.toList()..sort(), enterSelectsVisible: true,
              onTag: (tag) => _acceptQuickAssist(() => _insertQuickTag(tag)),
              onWord: (word) => _acceptQuickAssist(() => _insertQuickElement(word)), child: TextField(
              key: const ValueKey('quick-memo'),
              readOnly: _captureSaving,
              onTap: () => _draft.openAtCaret(context),
              inputFormatters: [TextInputFormatter.withFunction(_formatQuickMemo)],
              textInputAction: _desktopQuickMemo ? TextInputAction.done : TextInputAction.newline,
              onEditingComplete: _desktopQuickMemo ? () {} : null,
              onSubmitted: _desktopQuickMemo ? (_) => _submitQuickMemo() : null,
              controller: _draft,
              focusNode: _focus,
              minLines: 4,
              maxLines: MediaQuery.sizeOf(context).width < 760 ? 4 : null,
              onChanged: (_) => setState(() {}),
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
          if (_voiceDraft case final voice?) Row(children: [
            Expanded(child: VoicePlayer(key: ObjectKey(voice), load: () async => voice.bytes, durationMs: voice.durationMs)),
            IconButton(tooltip: '녹음 첨부 제거', onPressed: _captureSaving ? null : () => setState(() => _voiceDraft = null), icon: const Icon(Icons.close, size: 18)),
          ]),
          if (_photoDrafts.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final photo in _photoDrafts) SizedBox.square(dimension: 60, child: Stack(children: [
              Positioned.fill(child: InkWell(onTap: () => showPhoto(context, photo.bytes), child: ClipRRect(borderRadius: BorderRadius.circular(6),
                child: Image.memory(photo.bytes, fit: BoxFit.cover, cacheWidth: 180, errorBuilder: (_, error, stack) => const Icon(Icons.broken_image_outlined))))),
              Positioned(right: 0, top: 0, child: IconButton.filledTonal(tooltip: '사진 첨부 제거', constraints: const BoxConstraints.tightFor(width: 24, height: 24), padding: EdgeInsets.zero,
                onPressed: _captureSaving ? null : () => setState(() => _photoDrafts.remove(photo)), icon: const Icon(Icons.close, size: 14))),
            ])),
          ])),
          Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              textStyle: const TextStyle(fontSize: 12), visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: (_draft.text.trim().isEmpty && !_hasCapture) || _captureSaving || _locationBusy || _photoBusy ? null : (_mobileCapture ? _saveCapture : _save),
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
    final records = elements.records.values.where((record) => !record.tags.any(hiddenSearchTags.contains) && canBrowseThought(record) &&
      (record.indexLabel.toLowerCase().contains(_query.toLowerCase()) || record.text.toLowerCase().contains(_query.toLowerCase()) || record.tags.any((tag) => tag.contains(query))))
      .toList()..sort((a, b) {
        final closed = (a.hiddenFromSearch ? 1 : 0).compareTo(b.hiddenFromSearch ? 1 : 0);
        return closed != 0 ? closed : b.createdAt.compareTo(a.createdAt);
      });
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
          style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 1000 ? 13 : 14),
          onChanged: (value) => setState(() {
            _query = value; _memoRows = 5; _paragraphLimit = 5; _projectLimit = 5; _memoHasMore = false;
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
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(isProject ? '문서' : '문단', style: Theme.of(context).textTheme.labelMedium)),
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
                '${note.createdAt.month}월 ${note.createdAt.day}일 · ${note.project != null ? '문서' : '문단'}${note.tags.isEmpty ? '' : ' · ${note.tags.map((t) => '#$t').join(' ')}'}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _open(note),
            ),
          );

  Widget _desktopSidebar(BuildContext context) => SafeArea(top: false,
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
        onDeleteFolder: _deleteFolder,
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
          const KeyboardDismissAction(),
          if (GoogleAuthScope.maybeOf(context)?.identity != null)
            IconButton(tooltip: '프로필', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProfilePage(auth: GoogleAuthScope.maybeOf(context)!))), icon: ProfileAvatar(auth: GoogleAuthScope.maybeOf(context))),
          const SizedBox(width: 12),
        ],
        title: GestureDetector(onTap: MediaQuery.sizeOf(context).width >= 1000 ? () => navigateHome(context) : null, child: Text(
          'WEAVER',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        )),
        centerTitle: false,
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
                                    Expanded(child: RepaintBoundary(child: _composer(composerHeight))),
                                  ],
                                )
                              : Column(
                                  children: [
                                    RepaintBoundary(child: _composer(composerHeight)),
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

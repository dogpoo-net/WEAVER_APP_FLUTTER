part of 'inbox_page.dart';

/// Opens the same capture form used by the inbox, with a separate draft.
Future<ElementRecord?> showThoughtCapture(
  BuildContext context,
  WorkspaceStorage? storage,
) => showDialog<ElementRecord>(
  context: context,
  builder: (context) => _ThoughtCaptureDialog(storage: storage),
);

class _ThoughtCaptureDialog extends StatefulWidget {
  const _ThoughtCaptureDialog({required this.storage});
  final WorkspaceStorage? storage;

  @override
  State<_ThoughtCaptureDialog> createState() => _ThoughtCaptureDialogState();
}

class _ThoughtCaptureDialogState extends State<_ThoughtCaptureDialog>
    with _QuickMemoCapture<_ThoughtCaptureDialog> {
  @override
  WorkspaceStorage? get _captureStorage => widget.storage;
  @override
  bool get _captureDialog => true;

  @override
  void _captureCompleted(ElementRecord record) {
    Navigator.pop(context, record);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_captureSaving,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(child: _composer(double.infinity)),
      ),
    ),
  );
}

mixin _QuickMemoCapture<T extends StatefulWidget> on State<T> {
  WorkspaceStorage? get _captureStorage;
  GlobalKey? get _captureViewport => null;
  bool get _captureBlocked => false;
  bool get _captureDialog => false;
  Iterable<String> get _captureTags => elements.tags;
  ColorScheme get colors => Theme.of(context).colorScheme;
  Note? get _editing => null;
  void _recordCaptured(ElementRecord record, List<ElementBinding> links) {}
  void _captureCompleted(ElementRecord record);

  @override
  void initState() {
    super.initState();
    _draft.addListener(_imeUpdated);
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  final _draft = LabelTextController();
  final _draftTags = <String>{};
  ThoughtLocation? _draftLocation;
  bool _draftImportant = false;
  VoiceDraft? _voiceDraft;
  final _photoDrafts = <PhotoDraft>[];
  VoiceAttachment? _savedVoice;
  final _savedPhotos = <PhotoAttachment>[];
  bool _locationBusy = false, _captureSaving = false, _photoBusy = false;
  int _locationGeneration = 0;
  void _clearCapture() {
    _draftImportant = false;
    _locationGeneration++;
    _draftLocation = null;
    _locationBusy = false;
    _voiceDraft = null;
    _photoDrafts.clear();
    _savedVoice = null;
    _savedPhotos.clear();
  }

  void _captureError(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleLocation(bool enabled) async {
    final generation = ++_locationGeneration;
    if (!enabled) {
      setState(() {
        _locationBusy = false;
        _draftLocation = null;
      });
      return;
    }
    setState(() => _locationBusy = true);
    try {
      final location = await captureLocation();
      if (mounted && generation == _locationGeneration)
        setState(() => _draftLocation = location);
    } catch (error) {
      if (mounted && generation == _locationGeneration)
        _captureError(
          error is StateError
              ? error.message.toString()
              : '위치를 가져오지 못했습니다. 위치 권한과 기기 설정을 확인해주세요.',
        );
    } finally {
      if (mounted && generation == _locationGeneration)
        setState(() => _locationBusy = false);
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
        final photo = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );
        picked = photo == null ? [] : [photo];
      } else {
        picked = await picker.pickMultiImage(
          limit: remaining,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );
      }
      final photos = <PhotoDraft>[];
      for (final photo in picked.take(remaining)) {
        if (await photo.length() > 10 * 1024 * 1024) {
          _captureError('사진 한 장은 10MB 이하로 선택해주세요.');
          continue;
        }
        final bytes = await photo.readAsBytes();
        photos.add(PhotoDraft(bytes, photo.name));
      }
      if (mounted) setState(() => _photoDrafts.addAll(photos));
    } catch (_) {
      _captureError('사진을 가져오지 못했습니다. 사진 접근 권한을 확인해주세요.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  bool get _hasCapture =>
      _voiceDraft != null || _photoDrafts.isNotEmpty || _draftLocation != null;
  Future<void> _saveCapture() async {
    if (_captureSaving || _locationBusy || _photoBusy) return;
    if (_captureDialog) {
      try {
        await _captureStorage?.writable();
      } catch (error) {
        if (mounted) _captureError('생각을 저장하지 못했습니다. $error');
        return;
      }
      if (!mounted || _captureSaving || _locationBusy || _photoBusy) return;
    }
    final text = parseTaggedInput(_draft.text).text;
    if (text.isEmpty && !_hasCapture) {
      _captureError('생각 내용이나 첨부를 추가해주세요.');
      return;
    }
    if (_voiceDraft == null && _photoDrafts.isEmpty) {
      _save();
      return;
    }
    if (_captureStorage == null || _captureBlocked) {
      _captureError('저장소를 사용할 수 없습니다. 메모와 첨부는 유지됩니다.');
      return;
    }
    final existing = _editing == null
        ? elements.records[text]
        : elements.records[_editing!.content.trim()];
    if ((existing?.photos.length ?? 0) + _photoDrafts.length > 5) {
      _captureError('같은 내용의 생각에 이미 첨부된 사진을 포함해 최대 5장까지 저장할 수 있습니다.');
      return;
    }
    setState(() => _captureSaving = true);
    final written = <String>[];
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final voice = _voiceDraft;
      if (voice != null) {
        final id = 'voice-$stamp';
        written.add(id);
        await MediaStorage.write(
          id,
          voice.bytes,
          owner: _captureStorage?.owner,
        );
        _savedVoice = attachVoiceDraft(id, voice);
      }
      for (var i = 0; i < _photoDrafts.length; i++) {
        final photo = _photoDrafts[i], id = 'photo-$stamp-$i';
        written.add(id);
        await MediaStorage.write(
          id,
          photo.bytes,
          owner: _captureStorage?.owner,
        );
        _savedPhotos.add(PhotoAttachment(id, photo.name));
      }
      if (!mounted) throw StateError('Composer closed');
      if (!_save()) throw StateError('Memo not saved');
    } catch (_) {
      for (final id in written) {
        try {
          await MediaStorage.delete(id, owner: _captureStorage?.owner);
        } catch (_) {}
      }
      _savedVoice = null;
      _savedPhotos.clear();
      _captureError('첨부 저장에 실패했습니다. 작성한 메모와 첨부는 유지됩니다. 저장 공간을 확인해주세요.');
    } finally {
      if (mounted) setState(() => _captureSaving = false);
    }
  }

  final _focus = FocusNode();
  final _quickAssistKey = GlobalKey<CaretAssistState>();
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
  bool get _desktopQuickMemo =>
      _captureDialog ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  void _submitQuickMemo() {
    if (_assistSubmitUntil != null &&
        DateTime.now().isBefore(_assistSubmitUntil!))
      return;
    if (_pendingImeNewline ||
        (_explicitNewlineUntil != null &&
            DateTime.now().isBefore(_explicitNewlineUntil!)))
      return;
    if (_quickAssistKey.currentState?.acceptVisibleCandidate() == true) return;
    if (_draft.text.trim().isEmpty && !_hasCapture) return;
    _enterEchoText = _draft.text;
    _enterEchoUntil = DateTime.now().add(const Duration(milliseconds: 250));
    unawaited(_saveCapture());
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

  TextEditingValue _formatQuickMemo(
    TextEditingValue oldValue,
    TextEditingValue value,
  ) {
    if (!_desktopQuickMemo) return value;
    final now = DateTime.now();
    final beforeAssist = _assistInputBefore, completedAssist = _assistCompleted;
    if (_assistSubmitUntil != null &&
        now.isBefore(_assistSubmitUntil!) &&
        beforeAssist != null &&
        completedAssist != null &&
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
        if (value.text == echoed ||
            value.text == '$echoed\n' ||
            value.text == '$echoed\r\n') {
          return completedAssist;
        }
      }
      if (value.text == beforeAssist.text ||
          [
            newline(beforeAssist, '\n'),
            newline(beforeAssist, '\r\n'),
            newline(completedAssist, '\n'),
            newline(completedAssist, '\r\n'),
          ].contains(value.text)) {
        return completedAssist;
      }
    }
    if (_newlineEchoUntil != null &&
        now.isBefore(_newlineEchoUntil!) &&
        oldValue.text == _newlineEchoAfter &&
        (value.text == _newlineEchoBefore ||
            value.text == '$_newlineEchoAfter\n' ||
            value.text == '$_newlineEchoAfter\r\n')) {
      return oldValue.copyWith(composing: TextRange.empty);
    }
    if (oldValue.text.isEmpty &&
        _enterEchoUntil != null &&
        now.isBefore(_enterEchoUntil!) &&
        (value.text == _enterEchoText ||
            (_enterEchoSyllable != null && value.text == _enterEchoSyllable))) {
      return oldValue;
    }
    if (_pendingImeNewline ||
        (value.composing.isValid && !value.composing.isCollapsed))
      return value;
    if (oldValue.text.isEmpty &&
        _enterEchoUntil != null &&
        now.isBefore(_enterEchoUntil!) &&
        (value.text == '$_enterEchoText\n' ||
            value.text == '$_enterEchoText\r\n' ||
            value.text == '\n')) {
      _enterEchoText = null;
      return oldValue;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        (_explicitNewlineUntil != null &&
            now.isBefore(_explicitNewlineUntil!))) {
      return value;
    }
    var start = 0;
    while (start < oldValue.text.length &&
        start < value.text.length &&
        oldValue.text[start] == value.text[start]) {
      start++;
    }
    var oldEnd = oldValue.text.length, newEnd = value.text.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldValue.text[oldEnd - 1] == value.text[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final inserted = value.text.substring(start, newEnd);
    if (inserted == '\n' || inserted == '\r\n') {
      _queuePlatformEnter();
      return oldValue.copyWith(composing: TextRange.empty);
    }
    if (oldValue.composing.isValid &&
        !oldValue.composing.isCollapsed &&
        inserted.endsWith('\n')) {
      final length = inserted.endsWith('\r\n') ? 2 : 1;
      final text = value.text.replaceRange(newEnd - length, newEnd, '');
      _queuePlatformEnter();
      return value.copyWith(
        text: text,
        selection: TextSelection.collapsed(
          offset: (value.selection.extentOffset - length).clamp(0, text.length),
        ),
        composing: TextRange.empty,
      );
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
    if (_pendingImeNewline && _draft.value.composing.isCollapsed)
      _finishImeNewline();
    if (_pendingImeSave && _draft.value.composing.isCollapsed) {
      _finishImeSave();
    }
  }

  void _insertQuickNewline() {
    final value = _draft.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    _explicitNewlineUntil = DateTime.now().add(
      const Duration(milliseconds: 250),
    );
    setState(
      () => _draft.value = TextEditingValue(
        text: value.text.replaceRange(start, end, '\n'),
        selection: TextSelection.collapsed(offset: start + 1),
      ),
    );
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
      if (_draft.text.split('\n').length <= _imeNewlineLines)
        _insertQuickNewline();
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
    if (event is KeyDownEvent &&
        (!{
              LogicalKeyboardKey.process,
              LogicalKeyboardKey.shiftLeft,
              LogicalKeyboardKey.shiftRight,
              LogicalKeyboardKey.altLeft,
              LogicalKeyboardKey.altRight,
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.controlRight,
            }.contains(event.logicalKey) ||
            event.physicalKey == PhysicalKeyboardKey.backspace ||
            event.physicalKey == PhysicalKeyboardKey.delete)) {
      if (event.logicalKey != LogicalKeyboardKey.enter &&
          event.logicalKey != LogicalKeyboardKey.numpadEnter &&
          event.physicalKey != PhysicalKeyboardKey.enter &&
          event.physicalKey != PhysicalKeyboardKey.numpadEnter) {
        _enterEchoUntil = null;
        _enterEchoSyllable = null;
      }
      _newlineEchoBefore = null;
      _newlineEchoAfter = null;
      _newlineEchoUntil = null;
      _assistSubmitUntil = null;
      _assistInputBefore = null;
      _assistCompleted = null;
    }
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter;
    if (!_desktopQuickMemo || !enter) {
      return KeyEventResult.ignored;
    }
    // A new Enter that bubbles past assist is a distinct save request.
    if (event is KeyDownEvent) {
      _assistSubmitUntil = null;
      _assistInputBefore = null;
      _assistCompleted = null;
    }
    if (event is KeyUpEvent) {
      if (_pendingImeSave) _finishImeSave();
      if (_pendingImeNewline) _finishImeNewline();
      return HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    final value = _draft.value;
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        _quickAssistKey.currentState?.acceptVisibleCandidate() == true) {
      _pendingImeSave = false;
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (!keyboard.isShiftPressed && !keyboard.isAltPressed)
      _explicitNewlineUntil = null;
    if (value.composing.isValid && !value.composing.isCollapsed) {
      if (keyboard.isShiftPressed || keyboard.isAltPressed) {
        _pendingImeSave = false;
        _pendingImeNewline = true;
        _imeNewlineLines = value.text.split('\n').length;
        _explicitNewlineUntil = DateTime.now().add(
          const Duration(milliseconds: 250),
        );
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
    } else if (value.text.trim().isNotEmpty || _hasCapture) {
      _submitQuickMemo();
    }
    return KeyEventResult.handled;
  }

  Future<void> _acceptQuickAssist(FutureOr<void> Function() action) async {
    final before = _draft.value;
    final composing = _lastComposingValue;
    _assistComposingEcho = composing != null && composing.text == before.text
        ? composing.composing.textInside(composing.text)
        : null;
    final result = action();
    _pendingImeSave = false;
    _assistInputBefore = before;
    _assistCompleted = _draft.value;
    _assistSubmitUntil = DateTime.now().add(const Duration(milliseconds: 500));
    if (result is Future) {
      await result;
      if (!mounted) return;
      _assistCompleted = _draft.value;
      _assistSubmitUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
    }
  }

  Future<void> _insertQuickElement(String word) async {
    await insertAssistedLink(context, _draft, word);
    if (mounted) {
      setState(() {});
      _focus.requestFocus();
    }
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
      _draft.value = TextEditingValue(
        text: _draft.text.replaceRange(
          start,
          _draft.selection.end,
          replacement,
        ),
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
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
    final voiceOnly =
        cleaned.text.trim().isEmpty &&
        _voiceDraft != null &&
        _photoDrafts.isEmpty &&
        _draftLocation == null;
    var body = cleaned.text;
    if (body.trim().isEmpty && _hasCapture) {
      final title = attachmentMemoText(
        DateTime.now(),
        photos: _photoDrafts.isNotEmpty,
        audio: _voiceDraft != null,
        location: _draftLocation != null,
      );
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
      if (original == null) {
        _captureError('이미 삭제된 생각입니다.');
        return false;
      }
      final error = elements.update(
        original.text,
        input,
        tags: tags,
        inlineLinks: cleaned.links,
      );
      if (error != null) {
        _captureError(error);
        return false;
      }
      record = original;
    } else {
      record = elements.addLinked(input, cleaned.links, tags);
    }
    if (voiceOnly) record.voiceTextPending = true;
    record.important = _draftImportant;
    if (_draftLocation != null || _editing != null)
      record.location = _draftLocation;
    if (_savedVoice != null) {
      record.recordings.add(_savedVoice!);
      fillVoiceBody(record);
    }
    record.photos.addAll(_savedPhotos);
    final links = List<ElementBinding>.of(cleaned.links);
    setState(() {
      _recordCaptured(record, links);
      _draft.clear();
      _draftTags.clear();
      _clearCapture();
    });
    _captureCompleted(record);
    return true;
  }

  Widget _composer(double maxHeight) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: _captureDialog || MediaQuery.sizeOf(context).width < 760
          ? double.infinity
          : maxHeight,
    ),
    child: Card(
      color: colors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(_captureDialog ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_captureDialog)
                  const Spacer()
                else ...[
                  const Icon(Icons.edit_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _editing == null ? '빠른 메모' : '메모 다듬기',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
                ...[
                  IconButton(
                    key: const ValueKey('quick-important'),
                    tooltip: '중요 생각',
                    isSelected: _draftImportant,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: _draftImportant
                          ? colors.secondaryContainer
                          : null,
                    ),
                    onPressed: _captureSaving
                        ? null
                        : () => setState(
                            () => _draftImportant = !_draftImportant,
                          ),
                    icon: const Icon(Icons.priority_high, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('quick-location'),
                    tooltip: _locationBusy
                        ? '위치 요청 취소'
                        : _draftLocation == null
                        ? '위치 기록'
                        : '위치 기록 해제',
                    isSelected: _draftLocation != null,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: _draftLocation != null
                          ? colors.secondaryContainer
                          : null,
                    ),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _captureSaving
                        ? null
                        : () => _toggleLocation(
                            !_locationBusy && _draftLocation == null,
                          ),
                    selectedIcon: const Icon(Icons.location_on, size: 19),
                    icon: _locationBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_on_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '음성 메모',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _captureSaving || _photoBusy
                        ? null
                        : _recordVoice,
                    icon: const Icon(Icons.mic_none, size: 19),
                  ),
                  IconButton(
                    key: const ValueKey('quick-photo-menu'),
                    tooltip: '사진 업로드 (최대 5장)',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed:
                        _captureSaving || _photoBusy || _photoDrafts.length >= 5
                        ? null
                        : _pickPhotos,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 19,
                    ),
                  ),
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
                child: CaretAssist(
                  useThoughtLabels: true,
                  showShortcutHint: true,
                  key: _quickAssistKey,
                  controller: _draft,
                  focus: _focus,
                  words: labelAssistTargets(),
                  showWhenEmpty: false,
                  mobileViewportKey: _captureViewport,
                  tags: {..._captureTags, ..._draftTags}.toList()..sort(),
                  enterSelectsVisible: true,
                  onTag: (tag) =>
                      _acceptQuickAssist(() => _insertQuickTag(tag)),
                  onWord: (word) =>
                      _acceptQuickAssist(() => _insertQuickElement(word)),
                  child: TextField(
                    key: const ValueKey('quick-memo'),
                    readOnly: _captureSaving,
                    autofocus: _captureDialog,
                    onTap: () => _draft.openAtCaret(context),
                    inputFormatters: [
                      TextInputFormatter.withFunction(_formatQuickMemo),
                    ],
                    textInputAction: _desktopQuickMemo
                        ? TextInputAction.done
                        : TextInputAction.newline,
                    onEditingComplete: _desktopQuickMemo ? () {} : null,
                    onSubmitted: _desktopQuickMemo
                        ? (_) => _submitQuickMemo()
                        : null,
                    controller: _draft,
                    focusNode: _focus,
                    minLines: 4,
                    maxLines: _captureDialog
                        ? 6
                        : MediaQuery.sizeOf(context).width < 760
                        ? 4
                        : null,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: _captureDialog
                          ? '생각 기록'
                          : '단어나 생각을 남겨보세요 #독서 #아이디어',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_voiceDraft case final voice?)
              Row(
                children: [
                  Expanded(
                    child: VoicePlayer(
                      key: ObjectKey(voice),
                      load: () async => voice.bytes,
                      durationMs: voice.durationMs,
                      transcript: voice.transcript,
                      transcription: voice.transcription,
                    ),
                  ),
                  IconButton(
                    tooltip: '녹음 첨부 제거',
                    onPressed: _captureSaving
                        ? null
                        : () => setState(() => _voiceDraft = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            if (_photoDrafts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final photo in _photoDrafts)
                      SizedBox.square(
                        dimension: 60,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: InkWell(
                                onTap: () => showPhoto(context, photo.bytes),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    photo.bytes,
                                    fit: BoxFit.cover,
                                    cacheWidth: 180,
                                    errorBuilder: (_, error, stack) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton.filledTonal(
                                tooltip: '사진 첨부 제거',
                                constraints: const BoxConstraints.tightFor(
                                  width: 24,
                                  height: 24,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: _captureSaving
                                    ? null
                                    : () => setState(
                                        () => _photoDrafts.remove(photo),
                                      ),
                                icon: const Icon(Icons.close, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, _captureDialog ? 28 : 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed:
                    (_draft.text.trim().isEmpty && !_hasCapture) ||
                        _captureSaving ||
                        _locationBusy ||
                        _photoBusy
                    ? null
                    : _saveCapture,
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                label: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

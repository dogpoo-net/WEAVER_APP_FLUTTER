import '../capture/sketch_dialog.dart';
import '../capture/photo_image.dart';
import 'graph_layout.dart';
import 'memo_boxes.dart';
import 'canvas_geometry.dart' show alignedStackMembers;
import '../capture/location_capture.dart';
import '../capture/voice_transcription.dart';
import 'dart:collection';
import 'thought_colors.dart';
import '../capture/voice_dialog.dart';
import '../capture/attachment_picker.dart';
import '../capture/location_editor.dart' deferred as location_editor;
import 'deferred_screen.dart';
import 'memo_comments.dart';
import 'caret_assist.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'workspace_routes.dart';
import 'label_links.dart';
import 'element_binding.dart';
import 'document_markup.dart';
import 'tag_colors.dart';
import '../capture/location_preview.dart' deferred as location_preview;
import '../capture/photo_gallery.dart';
import '../capture/capture_models.dart';
import '../capture/media_storage.dart';
import '../capture/voice_player.dart';
import 'inline_tags.dart';
import 'paragraph_tag_input.dart';
import 'package:flutter/material.dart';

import 'project_page.dart';

import 'word_badge.dart';
import 'hashtags.dart';

part 'thought_reading.dart';

const noticeBoardLimit = 10;
const noticeBoardFullMessage = '알림판에는 생각을 최대 10개까지 등록할 수 있습니다.';

class ElementRecord {
  ElementRecord(this.text)
    : createdAt = DateTime.now(),
      id = 'element-${DateTime.now().microsecondsSinceEpoch}-${_next++}';
  ElementRecord.restored(
    this.id,
    this.text,
    this.createdAt, {
    Iterable<String> tags = const [],
  }) {
    this.tags.addAll(tags);
  }
  final Set<String> tags = {};
  List<ElementBinding> inlineLinks = [];
  Map<String, dynamic>? archivedDocument;
  final calendar = <String, int?>{};
  List<ThoughtPageData> extraPages = [];
  String? folder;
  ThoughtLocation? location;
  final List<VoiceAttachment> recordings = [];
  final List<PhotoAttachment> photos = [];
  bool important = false;
  DateTime? noticeBoardAt;
  int? noticeBoardOrder;
  bool voiceTextPending = false;
  bool hiddenFromSearch = false;
  int? labelColor;
  String indexLabel = '';
  bool labelOnLeft = false;
  int indexLabelColor = 0xFFFFF59D;
  String get title => indexLabel.isEmpty ? text : indexLabel;
  DateTime? deletedAt;
  static int _next = 0;
  final String id;
  String text;
  final DateTime createdAt;
}

class ElementSource {
  ElementSource(
    this.label,
    this.text, {
    this.isProject = false,
    this.project,
    this.paragraphIndex,
  });
  final WritingProject? project;
  final int? paragraphIndex;
  final bool isProject;
  final String label;
  final String text;
}

// Keep both keys in sync even when snapshot restore mutates records directly.
class _ElementRecords extends MapBase<String, ElementRecord> {
  final _values = <String, ElementRecord>{};
  final byId = <String, ElementRecord>{};
  @override Iterable<String> get keys => _values.keys;
  @override Iterable<ElementRecord> get values => _values.values;
  @override int get length => _values.length;
  @override ElementRecord? operator [](Object? key) => _values[key];
  @override void operator []=(String key, ElementRecord value) {
    final previous = _values[key];
    if (previous != null && identical(byId[previous.id], previous)) {
      byId.remove(previous.id);
    }
    _values[key] = value;
    byId[value.id] = value;
  }
  @override ElementRecord? remove(Object? key) {
    final previous = _values.remove(key);
    if (previous != null && identical(byId[previous.id], previous)) {
      byId.remove(previous.id);
    }
    return previous;
  }
  @override void clear() { _values.clear(); byId.clear(); }
}

class ElementStore extends ChangeNotifier {
  void Function(String oldText, String newText)? onRenamed;
  String? update(String oldText, String input, {Iterable<String>? tags, int? labelColor, bool? hiddenFromSearch, bool? important, bool? onNoticeBoard, String? indexLabel, bool? labelOnLeft, int? indexLabelColor, List<ElementBinding>? inlineLinks}) {
    final parsed = inlineLinks == null ? parseTaggedInput(input) : TaggedInput(input.trim(), {...?tags});
    if (parsed.text.isEmpty) return '생각 내용을 입력해주세요.';
    final record = records[oldText];
    if (record == null) return '이미 삭제된 생각입니다.';
    if (parsed.text != oldText && records.containsKey(parsed.text)) {
      return '같은 내용의 생각이 이미 있어요.';
    }
    final ordered = records.entries.map((e) => MapEntry(e.key == oldText ? parsed.text : e.key, e.value)).toList();
    if (onNoticeBoard == true && record.noticeBoardAt == null &&
        records.values.where((thought) => thought.noticeBoardAt != null).length >= noticeBoardLimit) {
      return noticeBoardFullMessage;
    }
    if (onNoticeBoard != null) {
      if (onNoticeBoard) {
        record.noticeBoardAt ??= DateTime.now().toUtc();
      } else {
        record.noticeBoardAt = null;
        record.noticeBoardOrder = null;
      }
    }
    if (inlineLinks != null) { record.inlineLinks = List.of(inlineLinks); }
    else if (parsed.text != oldText) { record.inlineLinks.clear(); }
    if (indexLabel != null) record.indexLabel = indexLabel.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (labelOnLeft != null) record.labelOnLeft = labelOnLeft;
    if (indexLabelColor != null) record.indexLabelColor = indexLabelColor;
    if(parsed.text!=oldText)record.voiceTextPending=false;
    record.text = parsed.text;
    if (labelColor != null) record.labelColor = labelColor;
    if (important != null) record.important = important;
    if (hiddenFromSearch != null) record.hiddenFromSearch = hiddenFromSearch;
    record.tags
      ..clear()
      ..addAll({...parsed.tags, ...?tags});
    records..clear()..addEntries(ordered);
    if (oldText != parsed.text) {
      renameWordColor(oldText, parsed.text);
      onRenamed?.call(oldText, parsed.text);
    }
    notifyListeners();
    return null;
  }

  void projectChanged(WritingProject project) { indexProject(project); notifyListeners(); }

  void indexProject(WritingProject project) {
    if (project.document != null) {
      sources[project] = [ElementSource(project.name, project.document!, isProject: true, project: project)];
      return;
    }
    sources[project] = [
      for (var i = 0; i < project.paragraphs.length; i++)
        ElementSource(
          '${project.name} · 문단 ${i + 1}',
          project.paragraphs[i].text,
          isProject: true,
          project: project,
          paragraphIndex: i,
        ),
    ];
  }

  int deletionRevision = 0;
  void remove(String word) => removeAll([word]);

  void removeAll(Iterable<String> words) {
    final deletedAt = DateTime.now();
    var changed = false;
    for (final word in words) {
      final removed = records.remove(word);
      if (removed == null) continue;
      removed.deletedAt = deletedAt;
      removed.noticeBoardAt = null;
      removed.noticeBoardOrder = null;
      trash[removed.id] = removed;
      changed = true;
    }
    if (changed) {
      deletionRevision++;
      notifyListeners();
    }
  }

  final Map<String, ElementRecord> trash = {};
  final _records = _ElementRecords();
  Map<String, ElementRecord> get records => _records;
  ElementRecord? byId(String id) => _records.byId[id];
  final Map<Object, List<ElementSource>> sources = {};
  ElementRecord add(String text, {bool replaceTags = false}) {
    final parsed = parseTaggedInput(text);
    final clean = parsed.text;
    if (clean.isEmpty) throw ArgumentError('Empty element');
    ensureWordColor(clean);
    final record = records.putIfAbsent(clean, () => ElementRecord(clean));
    if (replaceTags) record.tags.clear();
    record.tags.addAll(parsed.tags);
    return record;
  }

  ElementRecord addLinked(String text, List<ElementBinding> links, Iterable<String> tags) {
    if (text.trim().isEmpty) throw ArgumentError('Empty thought');
    ensureWordColor(text);
    final record = records.putIfAbsent(text, () => ElementRecord(text));
    record.inlineLinks = List.of(links); record.tags.addAll(tags);
    return record;
  }
  void refreshVisibility() => notifyListeners();
  List<String> get words => records.keys.toList();
  bool isSearchable(String word) {
    final record = records[word];
    return record == null || !record.hiddenFromSearch;
  }
  List<String> get visibleWords => words.where(isSearchable).toList();
  void setHidden(String word, bool hidden) {
    final record = records[word];
    if (record == null) return;
    record.hiddenFromSearch = hidden;
    notifyListeners();
  }
  List<String> get tags =>
      records.values.expand((r) => r.tags).toSet().toList()..sort();
  List<({int start, int end, String word})> matches(String text) {
    final result = <({int start, int end, String word})>[];
    final ordered = words..sort((a, b) => b.length.compareTo(a.length));
    var cursor = 0;
    while (cursor < text.length) {
      String? match;
      for (final word in ordered) {
        if (text.startsWith(word, cursor)) {
          match = word;
          break;
        }
      }
      if (match == null) {
        cursor++;
      } else {
        result.add((start: cursor, end: cursor + match.length, word: match));
        cursor += match.length;
      }
    }
    return result;
  }

  void clear() {
    records.clear();
    trash.clear();
    sources.clear();
  }
}

final elements = ElementStore();

Future<void> showElementMetadata(BuildContext context, String word, {VoidCallback? onSaved, GraphLayout? canvasLayout}) async {
  // Live workspace sync already maintains the local snapshot. Opening a
  // detail must not wait for an extra save/refresh round trip.
  if (!context.mounted) return;
  final selected = elements.records[word];
  if (selected == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('다른 기기에서 삭제된 생각입니다.'))); return; }
  var members = [selected];
  final layouts = canvasLayout != null ? [canvasLayout] : [
    pageGraphLayout.blockLayout,
    for (final box in memoBoxes.where((box) => box.elementIds.contains(selected.id))) box.layout.blockLayout,
  ];
  for (final layout in layouts) {
    final ids = alignedStackMembers(selected.id, layout.positions, groups: layout.stackGroups);
    final ordered = ids.map(elements.byId).nonNulls.toList();
    if (ordered.length < 2) continue;
    ordered.sort((a, b) {
      final vertical = layout.positions[a.id]!.dy.compareTo(layout.positions[b.id]!.dy);
      if (vertical != 0) return vertical;
      return layout.layers.indexOf(b.id).compareTo(layout.layers.indexOf(a.id));
    });
    members = ordered;
    break;
  }
  final pages = [for (final member in members)
    (record: member, page: ThoughtPageData.first(member))];
  final selectedPage = await showDialog<int>(context: context, builder: (_) => _ThoughtReading(pages, pages.indexWhere((p) => p.record == selected)));
  if (selectedPage == null || !context.mounted) return;
  final record = pages[selectedPage].record;
  if (elements.byId(record.id) != record) return;
  word = record.text;
  final owner=MediaStorage.activeOwner;
  voiceBodyEditors.update(record.id,(n)=>n+1,ifAbsent:()=>1);
  try{
    await showDialog<void>(context:context,builder:(_)=>_ElementMetadata(word:word,onSaved:onSaved, initialPage:0));
  }finally{
    final remaining=(voiceBodyEditors[record.id]??1)-1;
    if(remaining==0){voiceBodyEditors.remove(record.id);}else{voiceBodyEditors[record.id]=remaining;}
    final latest=elements.byId(record.id);
    if(owner==MediaStorage.activeOwner && latest!=null && fillVoiceBody(latest)){
      try{await saveWorkspaceContent?.call();}catch(_){/* Keep local text for the normal sync retry. */}
    }
  }
}

class _ElementMetadata extends StatefulWidget {
  const _ElementMetadata({required this.word, required this.initialPage, this.onSaved});
  final VoidCallback? onSaved;
  final int initialPage;
  final String word;
  @override
  State<_ElementMetadata> createState() => _ElementMetadataState();
}

class _ElementMetadataState extends State<_ElementMetadata> {
  late final LabelTextController _editor;
  late final TextEditingController _labelEditor;
  bool _labelOnLeft = false;
  int _indexLabelColor = 0xFFFFF59D;
  final _contentScroll = ScrollController();
  final _editorFocus = FocusNode();
  late final Set<String> _tags;
  bool _movingTags = false;
  late String _word;
  int? _labelColor;
  late bool _closed;
  bool? _noticeBoardChange;
  String? _error;
  final _photoUploads=<String,List<PhotoDraft>>{};
  final _audioUploads=<String,List<VoiceDraft>>{};
  final _locationEdits=<String,ThoughtLocation?>{};
  final _removedPhotos=<String,Set<String>>{};
  final _removedAudio=<String,Set<String>>{};
  ThoughtLocation? _locationFor(ElementRecord r)=>_locationEdits.containsKey(r.id)?_locationEdits[r.id]:r.location;
  List<PhotoAttachment> _photosFor(ElementRecord r)=>r.photos.where((p)=>!(_removedPhotos[r.id]?.contains(p.id)??false)).toList();
  List<VoiceAttachment> _audioFor(ElementRecord r)=>(_audioUploads[r.id]?.isNotEmpty??false)?[]:r.recordings.where((a)=>!(_removedAudio[r.id]?.contains(a.id)??false)).toList();
  String? _pinnedPhoto;
  double _pinSize = 48;
  bool _pinChanged = false;
  bool _attachmentBusy=false,_captureModalOpen=false;
  bool get _canAttach=>memoCommentRequest==null||memoCommentsWritable;
  late final String? _mediaOwner;
  Future<void> _attach(ElementRecord record,String type) async {
    if(_attachmentBusy||!_canAttach)return;
    setState((){_attachmentBusy=true;_captureModalOpen=type!='photo';});
    try {
      if(type=='sketch'){
        if (_photosFor(record).length + (_photoUploads[record.id]?.length ?? 0) >= 5) throw StateError('사진은 최대 5장까지 저장할 수 있습니다.');
        final sketch = await showSketchDialog(context);
        if(mounted && sketch!=null)setState(()=>_photoUploads.putIfAbsent(record.id,()=>[]).add(sketch));
      }else if(type=='photo'){
        final drafts=await pickPhotoUploads(5-_photosFor(record).length-(_photoUploads[record.id]?.length??0));
        if(mounted)setState(()=>_photoUploads.putIfAbsent(record.id,()=>[]).addAll(drafts));
      }else if(type=='audio'){
        final draft=await showVoiceRecorder(context);
        if(mounted&&draft!=null)setState(()=>_audioUploads[record.id]=[draft]);
      }else{
        if (locationOffline) {
          if (_locationFor(record) != null) return;
          final point = await captureLocation();
          if (mounted) setState(() => _locationEdits[record.id] = point);
          return;
        }
        if (!await loadScreen(context, location_editor.loadLibrary) || !mounted) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        final draft=await location_editor.showLocationEditor(context,initial:_locationFor(record));
        if(mounted&&draft!=null)setState(()=>_locationEdits[record.id]=draft.location);
      }
    }catch(e){if(mounted)setState(()=>_error='$e');}
    finally{if(mounted)setState((){_attachmentBusy=false;_captureModalOpen=false;});}
  }
  final _offlineStatus = locationOfflineStatus;
  void _connectionChanged() { if (mounted) setState(() {}); }
  @override
  void initState() {
    super.initState();
    _offlineStatus?.addListener(_connectionChanged);
    _mediaOwner=MediaStorage.activeOwner;
    _word = widget.word;
    final record = elements.records[_word]!;
    final pin = record.photos.where((p) => p.canvasSize != null).firstOrNull;
    _pinnedPhoto = pin?.id; _pinSize = pin?.canvasSize ?? 48;
    _labelEditor = TextEditingController(text: record.indexLabel);
    _labelOnLeft = record.labelOnLeft; _indexLabelColor = record.indexLabelColor;
    _tags = Set.of(record.tags);
    _labelColor = record.labelColor; _closed = record.hiddenFromSearch;
    _editor = LabelTextController(record.text, record.inlineLinks)..addListener(_extractTags);
    _pages = [ThoughtPageData.first(record), ...record.extraPages];
    _loadPage(widget.initialPage.clamp(0, _pages.length - 1));
  }

  late final List<ThoughtPageData> _pages;
  int _page = 0;
  void _capturePage() {
    final clean = cleanLinkedInput(_editor);
    _tags.addAll(clean.tags);
    _pages[_page] = ThoughtPageData(clean.text, _labelEditor.text.trim(), _labelOnLeft, _indexLabelColor, clean.links);
  }
  void _loadPage(int index) {
    _page = index;
    final page = _pages[index];
    _movingTags = true;
    _editor.loadDocument(page.text, page.links);
    _movingTags = false;
    _labelEditor.text = page.label;
    _labelOnLeft = page.left;
    _indexLabelColor = page.color;
    _error = null;
  }
  void _turn(int index) {
    setState(() {
      _capturePage();
      _loadPage(index);
    });
  }

  void _extractTags() {
    if (_movingTags) return;
    final completed = takeCompletedParagraphTags(_editor.value, consumeLineBreak: true, protected: _editor.bindings.map((b) => TextRange(start: b.start, end: b.end)));
    if (completed.tags.isEmpty) return;
    _movingTags = true;
    try {
      setState(() {
        _tags.addAll(completed.tags);
        int offset(int n) => n - completed.removed.fold<int>(0, (sum, r) => sum + (n - r.start).clamp(0, r.end - r.start));
        final links = [for (final b in _editor.bindings) ElementBinding(b.id, offset(b.start), offset(b.end))];
        _editor.loadDocument(completed.value.text, links, selection: completed.value.selection);
        _error = null;
      });
    } finally { _movingTags = false; }
  }

  @override
  void dispose() {
    _offlineStatus?.removeListener(_connectionChanged);
    _editorFocus.dispose();
    _editor.dispose();
    _labelEditor.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _word;
    final element = elements.records[word];
    if (element == null) return const SizedBox.shrink();
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final captureStyle = IconButton.styleFrom(
      minimumSize: const Size(36, 36), maximumSize: const Size(36, 36),
      padding: EdgeInsets.zero, visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final attachmentActionStyle = IconButton.styleFrom(
      minimumSize: const Size.square(40),
      fixedSize: const Size.square(40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final compact = TextButton.styleFrom(minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 40, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: InlineTags(key: const ValueKey('element-tags'), tags: _tags,
          onRemove: (tag) => setState(() => _tags.remove(tag)))),
        IconButton(key: const ValueKey('thought-color'), tooltip: '생각 색상 변경',
          style: IconButton.styleFrom(fixedSize: const Size(32, 32),
            padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          visualDensity: VisualDensity.compact, icon: Container(width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _closed ? wordBackgroundColor(context, word, closed: true) : _labelColor == null ? wordBackgroundColor(context, word, closed: false) : thoughtBackgroundForColor(context,Color(_labelColor!)),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant))),
          onPressed: _closed ? null : () async {
            final color = await pickThoughtColor(context, _labelColor == null ? null : Color(_labelColor!));
            if (color == null || !mounted) return;
            setState(() => _labelColor = color.toARGB32());
          }),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: SizedBox(
        width: mobile ? MediaQuery.sizeOf(context).width : 440,
        child: SingleChildScrollView(controller: _contentScroll, primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.only(top: 4), child: TextField(key: const ValueKey('thought-label-editor'), controller: _labelEditor,
                maxLines: 1, style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(labelText: '라벨 붙이기', hintText: '라벨 내용', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  suffixIconConstraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  suffixIcon: IconButton(key: const ValueKey('index-label-color'), tooltip: '라벨 색상',
                    padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: Icon(Icons.circle, color: Color(_indexLabelColor).withValues(alpha: .6), size: 22),
                    onPressed: () async {
                      final color = await pickHashtagColor(context, '라벨', Color(_indexLabelColor), prefix: '');
                      if (color != null && mounted) setState(() => _indexLabelColor = color.toARGB32());
                    })))),
              const SizedBox(height: 4),
              TextFieldTapRegion(child: Row(children: [
                const Text('붙일 방향'), const Spacer(),
                for (final left in [true, false]) IconButton(
                  key: ValueKey(left ? 'label-left' : 'label-right'), tooltip: left ? '왼쪽에 붙이기' : '오른쪽에 붙이기',
                  isSelected: _labelOnLeft == left,
                  style: IconButton.styleFrom(backgroundColor: _labelOnLeft == left ? Theme.of(context).colorScheme.secondaryContainer : Colors.transparent,
                    foregroundColor: _labelOnLeft == left ? Theme.of(context).colorScheme.onSecondaryContainer : null,
                    visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _labelOnLeft = left), icon: Icon(left ? Icons.west : Icons.east)),
              ])),
              const SizedBox(height: 8),
              CaretAssist(controller: _editor, focus: _editorFocus, useThoughtLabels: true,
                words: labelAssistTargets().where((word) => word != _word).toList(), tags: {...elements.tags, ..._tags}.toList(),
                showWhenEmpty: false, explicitSelectionOnly: true,
                onWord: (word) async { await insertAssistedLink(context, _editor, word, useCaretTitle: true); if (mounted) _editorFocus.requestFocus(); },
                onTag: (tag) {
                  final token = tagPrefix(_editor.value); if (token.isEmpty) return;
                  final end = _editor.selection.end;
                  final text = _editor.text.replaceRange(end - token.length, end, '#$tag ');
                  _editor.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: end - token.length + tag.length + 2));
                  _editorFocus.requestFocus();
                }, child: TextField(
                key: const ValueKey('element-editor'), focusNode: _editorFocus,
                inputFormatters: [TextInputFormatter.withFunction((before, next) {
                  if (!before.selection.isValid || tagPrefix(before).isEmpty || (next.composing.isValid && !next.composing.isCollapsed)) return next;
                  final start = before.selection.start, end = before.selection.end;
                  for (final newline in ['\n', '\r\n']) {
                    if (next.text == before.text.replaceRange(start, end, newline)) {
                      return next.copyWith(text: before.text.replaceRange(start, end, ' '), selection: TextSelection.collapsed(offset: start + 1));
                    }
                  }
                  return next;
                })],
                controller: _editor,
                onTap: () => _editor.openAtCaret(context),
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: '생각 내용',
                  hintText: '생각 내용 #태그',
                  errorText: _error,
                ),
                onChanged: (_) {
                  setState(() => _error = null);
                },
              )),
              const SizedBox(height: 8),
              if (_pages.length > 1) Row(children: [
                Text('${_page + 1} / ${_pages.length}'),
                const Spacer(),
                IconButton(tooltip: '이전 페이지', icon: const Icon(Icons.chevron_left),
                  onPressed: _page == 0 ? null : () => _turn(_page - 1)),
                IconButton(tooltip: '다음 페이지', icon: const Icon(Icons.chevron_right),
                  onPressed: _page + 1 >= _pages.length || cleanLinkedInput(_editor).text.isEmpty ? null : () => _turn(_page + 1)),
              ]),
              const Divider(key:ValueKey('element-attachments-divider'),height:9,thickness:1),
              Row(children:[
                IconButton(tooltip:locationOffline && _locationFor(element)!=null ? '위치 수정은 온라인에서 가능해요' : '위치 기록',style:captureStyle,onPressed:_attachmentBusy||!_canAttach||(locationOffline && _locationFor(element)!=null)?null:()=>_attach(element,'location'),icon:const Icon(Icons.location_on_outlined,size:20)),
                IconButton(tooltip:'음성 녹음',style:captureStyle,onPressed:_attachmentBusy||!_canAttach?null:()=>_attach(element,'audio'),icon:const Icon(Icons.mic_none,size:20)),
                IconButton(tooltip:'스케치',style:captureStyle,onPressed:_attachmentBusy||!_canAttach?null:()=>_attach(element,'sketch'),icon:const Icon(Icons.draw_outlined,size:20)),
                IconButton(tooltip:'사진 업로드',style:captureStyle,onPressed:_attachmentBusy||!_canAttach?null:()=>_attach(element,'photo'),icon:const Icon(Icons.add_photo_alternate_outlined,size:20)),
                IconButton(tooltip: '생각 닫기', style: captureStyle, isSelected: _closed,
                  icon: const Icon(Icons.task_alt_outlined), selectedIcon: const Icon(Icons.check_circle),
                  onPressed: () => setState(() => _closed = !_closed)),
                const Spacer(),
                ValueListenableBuilder<Map<String,int>>(
                  valueListenable:memoCommentCounts,
                  builder:(context,counts,child)=>TextButton(
                    onPressed:()=>showMemoComments(context,element.id),
                    child:Text('댓글 ${counts[element.id]??0}'))),
              ]),
              if(_attachmentBusy&&!_captureModalOpen)const LinearProgressIndicator(),
              if (_locationFor(element) case final location?) Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children:[Expanded(child:Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed: locationOffline ? null : () async {
                  if (!await loadScreen(context, location_preview.loadLibrary) || !mounted) return;
                  if (ModalRoute.of(context)?.isCurrent == false) return;
                  await location_preview.showLocationPreview(context, location, onChanged: _canAttach ? (updated) {
                    if (mounted) setState(() => _locationEdits[element.id] = updated);
                  } : null);
                },
                  icon: const Icon(Icons.location_on_outlined, size: 18), label: Text(locationOffline ? '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}' : '지도 보기')))),
                  IconButton(style:attachmentActionStyle,tooltip:'위치 삭제',onPressed:_attachmentBusy||!_canAttach?null:()=>setState(()=>_locationEdits[element.id]=null),icon:const Icon(Icons.delete_outline)),
                ])),
              for(final audio in _audioUploads[element.id]??<VoiceDraft>[])VoicePlayer(key:ObjectKey(audio),load:()async=>audio.bytes,durationMs:audio.durationMs,transcript:audio.transcript,transcription:audio.transcription,textStyle:Theme.of(context).textTheme.labelLarge,actionStyle:attachmentActionStyle,
                trailing:IconButton(style:attachmentActionStyle,tooltip:'음성 삭제',onPressed:_attachmentBusy||!_canAttach?null:()=>setState((){_audioUploads[element.id]!.clear();_removedAudio[element.id]=element.recordings.map((a)=>a.id).toSet();}),icon:const Icon(Icons.delete_outline))),
              for(final clip in _audioFor(element))VoicePlayer(key:ValueKey(clip.id),load:()=>MediaStorage.read(clip.id),durationMs:clip.durationMs,transcript:clip.transcript,transcription:clip.transcription,textStyle:Theme.of(context).textTheme.labelLarge,actionStyle:attachmentActionStyle,
                onTranscribe:_canAttach && voiceAudioRequest!=null?()async{try{await retrySavedVoice(element.id,clip.id);}finally{if(mounted)setState((){});}}:null,
                trailing:IconButton(style:attachmentActionStyle,tooltip:'음성 삭제',onPressed:_attachmentBusy||!_canAttach?null:()=>setState(()=>_removedAudio.putIfAbsent(element.id,()=>{}).add(clip.id)),icon:const Icon(Icons.delete_outline))),
              if (_photosFor(element).isNotEmpty) Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                PopupMenuButton<String>(tooltip: '사진붙이기', child: const Padding(padding: EdgeInsets.all(8),child: Text('사진붙이기')),
                  enabled: _canAttach && !_attachmentBusy,
                  itemBuilder: (_) => [
                    for (final p in _photosFor(element)) CheckedPopupMenuItem(value: p.id,
                        checked: p.id == _pinnedPhoto, child: Text(p.name)),
                    const PopupMenuItem(value: '', child: Text('표시 해제')),
                  ], onSelected: (id) => setState(() { _pinChanged = true; _pinnedPhoto = id; })),
                if (_photosFor(element).any((p) => p.id == _pinnedPhoto))
                  SizedBox(width: 130, child: Slider(min: 24, max: 120, value: _pinSize,
                    semanticFormatterCallback: (v) => '사진 크기 ${v.round()}',
                    onChanged: !_canAttach ? null : (v) => setState(() { _pinChanged = true; _pinSize = v; }))),
              ]),
              if(_photosFor(element).isNotEmpty||(_photoUploads[element.id]?.isNotEmpty??false))Padding(padding:const EdgeInsets.symmetric(vertical:8),child:PhotoGallery(
                photos:_photosFor(element),
                onDelete:_attachmentBusy||!_canAttach?null:(photo)=>setState(()=>_removedPhotos.putIfAbsent(element.id,()=>{}).add(photo.id)),
                trailing:[
                for(final photo in _photoUploads[element.id]??<PhotoDraft>[])SizedBox.square(dimension:88,child:Stack(fit:StackFit.expand,children:[
                  photoImage(photo.bytes,fit:BoxFit.cover,errorBuilder:(_,error,stack)=>const Icon(Icons.broken_image)),
                  Positioned(top:2,right:2,child:PhotoRemoveButton(onPressed:_attachmentBusy||!_canAttach?null:()=>setState(()=>_photoUploads[element.id]!.remove(photo)))),
                ])),
              ])),
            ],
          ),
        ),
      )),
        const Padding(padding: EdgeInsets.only(top: 8),
          child: Divider(key: ValueKey('element-actions-divider'), height: 1, thickness: 1)),
        Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
          if (_canAttach) IconButton(
            tooltip: (_noticeBoardChange ?? (element.noticeBoardAt != null))
                ? '알림판 등록 해제' : '알림판에 등록',
            isSelected: _noticeBoardChange ?? (element.noticeBoardAt != null),
            style: captureStyle,
            icon: const Icon(Icons.push_pin_outlined, size: 18),
            selectedIcon: const Icon(Icons.push_pin, size: 18),
            onPressed: _attachmentBusy ? null : () {
              final registered = _noticeBoardChange ?? (element.noticeBoardAt != null);
              if (!registered && element.noticeBoardAt == null &&
                  elements.records.values.where((thought) => thought.noticeBoardAt != null).length >= noticeBoardLimit) {
                setState(() => _error = noticeBoardFullMessage);
                return;
              }
              setState(() {
                _noticeBoardChange = !registered;
                if (_error == noticeBoardFullMessage) _error = null;
              });
            },
          ),
          Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[
          Flexible(child: Text(workspaceMemoAuthor?.call(element.id) ?? '작성자 정보 없음',
            key: const ValueKey('element-author'), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall)),
          Text(' ', style: Theme.of(context).textTheme.bodySmall),
          Text(element.createdAt.toLocal().toString().split('.').first,
            key: const ValueKey('element-created-at'), style: Theme.of(context).textTheme.bodySmall),
          ])),
        ])),
      ]),
      actions: [
        FilledButton.tonal(
          style: compact,
          onPressed: _attachmentBusy ? null : () async {
            if(_mediaOwner!=MediaStorage.activeOwner){setState(()=>_error='워크스페이스가 변경되었습니다. 다시 열어주세요.');return;}
            _capturePage();
            final cleaned = _pages.first;
            if (_pages.take(_pages.length - 1).any((page) => page.text.isEmpty)) {
              setState(() => _error = '빈 페이지에 내용을 입력해주세요.');return;
            }
            if(cleaned.text.trim().isEmpty || cleaned.text!=word && elements.records.containsKey(cleaned.text)){
              setState(()=>_error='생각 내용을 확인해주세요. 같은 내용의 생각은 중복 저장할 수 없습니다.');return;
            }
            final deletesSavedData=element.photos.any((p)=>_removedPhotos[element.id]?.contains(p.id)??false)||
              element.recordings.any((a)=>(_removedAudio[element.id]?.contains(a.id)??false)||(_audioUploads[element.id]?.isNotEmpty??false))||
              element.location!=null&&_locationEdits.containsKey(element.id)&&_locationEdits[element.id]==null;
            if(deletesSavedData){
              setState((){_attachmentBusy=true;_captureModalOpen=true;});
              final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
                content:const Text('삭제된 데이터가 있습니다. 저장하시겠습니까?'),
                actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('취소')),
                  FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('저장'))]));
              if(!mounted)return;
              _captureModalOpen=false;
              if(confirmed!=true){setState(()=>_attachmentBusy=false);return;}
              if(_mediaOwner!=MediaStorage.activeOwner){setState((){_attachmentBusy=false;_error='워크스페이스가 변경되었습니다. 다시 열어주세요.';});return;}
            }
            final written=<String>[],photos=<PhotoAttachment>[],voices=<VoiceAttachment>[];
            setState(()=>_attachmentBusy=true);
            try{
              final stamp=DateTime.now().microsecondsSinceEpoch;
              for(final photo in _photoUploads[element.id]??<PhotoDraft>[]){
                final id='photo-$stamp-${written.length}';written.add(id);await MediaStorage.write(id,photo.bytes,owner:_mediaOwner);photos.add(PhotoAttachment(id,photo.name));
              }
              for(final audio in _audioUploads[element.id]??<VoiceDraft>[]){
                final id='voice-$stamp-${written.length}';written.add(id);await MediaStorage.write(id,audio.bytes,owner:_mediaOwner);voices.add(attachVoiceDraft(id,audio));
              }
              if(!mounted||_mediaOwner!=MediaStorage.activeOwner||elements.records[word]?.id!=element.id)throw StateError('편집 화면이나 워크스페이스가 변경되었습니다.');
              if(_photosFor(elements.records[word]!).length+photos.length>5)throw StateError('사진은 최대 5장까지 저장할 수 있습니다.');
            }catch(e){
              for(final id in written){try{await MediaStorage.delete(id,owner:_mediaOwner);}catch(_){}}
              if(mounted)setState((){_attachmentBusy=false;_error='첨부 저장에 실패했습니다. $e';});return;
            }
            final error = elements.update(word, cleaned.text, inlineLinks: cleaned.links, tags: _tags, labelColor: _labelColor, hiddenFromSearch: _closed, onNoticeBoard: _noticeBoardChange, indexLabel: cleaned.label, labelOnLeft: cleaned.left, indexLabelColor: cleaned.color);
            if (error != null) {
              for(final id in written){await MediaStorage.delete(id,owner:_mediaOwner);}
              if(mounted)setState(() { _attachmentBusy=false;_error = error; });
              return;
            }
            final savedRecord=elements.records[cleaned.text]!;
            savedRecord.extraPages = _pages.skip(1).where((page) => page.text.isNotEmpty).toList();
            final removedIds=<String>{...?_removedPhotos[element.id],...?_removedAudio[element.id],if(voices.isNotEmpty)...savedRecord.recordings.map((a)=>a.id)};
            savedRecord.photos.removeWhere((p)=>removedIds.contains(p.id));
            savedRecord.recordings.removeWhere((a)=>removedIds.contains(a.id));
            if (_pinChanged) {
              for (var i = 0; i < savedRecord.photos.length; i++) {
                final p = savedRecord.photos[i];
                savedRecord.photos[i] = PhotoAttachment(p.id, p.name, canvasSize: p.id == _pinnedPhoto ? _pinSize : null);
              }
            }
            savedRecord.photos.addAll(photos);savedRecord.recordings.addAll(voices);
            for(final id in removedIds){
              final referenced=[...elements.records.values,...elements.trash.values].any((r)=>r.photos.any((p)=>p.id==id)||r.recordings.any((a)=>a.id==id));
              if(!referenced)unawaited(MediaStorage.delete(id,owner:_mediaOwner).catchError((Object _){}));
            }
            if(_locationEdits.containsKey(element.id))savedRecord.location=_locationEdits[element.id];
            elements.refreshVisibility();
            if(!context.mounted)return;
            final messenger=ScaffoldMessenger.of(context);
            Navigator.pop(context);
            widget.onSaved?.call();
            final save=saveWorkspaceContent;
            if(save!=null){unawaited(save().catchError((Object error){
              if(messenger.mounted)messenger.showSnackBar(SnackBar(content:Text('변경은 기기에 보관했습니다. 서버 저장에 실패했습니다. $error')));
            }));}
          },
          child: const Text('저장'),
        ),
        TextButton(
          style: compact,
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('생각을 삭제할까요?'),
                content: const Text('휴지통으로 이동합니다. 문서의 글은 유지됩니다.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              elements.remove(word);
              Navigator.pop(context);
            }
          },
          child: const Text('삭제'),
        ),
        TextButton(
          style: compact,
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class ElementText extends StatelessWidget {
  const ElementText(this.text, {super.key, this.style, this.focusOffset});
  final String text;
  final TextStyle? style;
  final int? focusOffset;
  @override
  Widget build(BuildContext context) => DocumentMarkup(text: text,
    links: elements.records[text]?.inlineLinks ?? const [], style: style, formatting: false);
}

/// Important thoughts first; newest thoughts first within each priority.
int compareThoughtPriority(ElementRecord a, ElementRecord b) {
  final priority = (b.important ? 1 : 0).compareTo(a.important ? 1 : 0);
  if (priority != 0) return priority;
  final date = b.createdAt.compareTo(a.createdAt);
  return date != 0 ? date : a.id.compareTo(b.id);
}

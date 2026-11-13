import 'caret_assist.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'workspace_routes.dart';
import 'label_links.dart';
import 'element_binding.dart';
import 'document_markup.dart';
import 'tag_colors.dart';
import '../capture/location_preview.dart';
import '../capture/photo_gallery.dart';
import '../capture/capture_models.dart';
import '../capture/media_storage.dart';
import '../capture/voice_player.dart';
import 'inline_tags.dart';
import 'paragraph_tag_input.dart';
import 'package:flutter/material.dart';

import 'project_page.dart';
import 'project_folders.dart';

import 'word_badge.dart';
import 'hashtags.dart';

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
  String? folder;
  ThoughtLocation? location;
  final List<VoiceAttachment> recordings = [];
  final List<PhotoAttachment> photos = [];
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

class ElementStore extends ChangeNotifier {
  void Function(String oldText, String newText)? onRenamed;
  String? update(String oldText, String input, {Iterable<String>? tags, int? labelColor, bool? hiddenFromSearch, String? indexLabel, bool? labelOnLeft, int? indexLabelColor, List<ElementBinding>? inlineLinks}) {
    final parsed = inlineLinks == null ? parseTaggedInput(input) : TaggedInput(input.trim(), {...?tags});
    if (parsed.text.isEmpty) return '생각 내용을 입력해주세요.';
    final record = records[oldText];
    if (record == null) return '이미 삭제된 생각입니다.';
    if (parsed.text != oldText && records.containsKey(parsed.text)) {
      return '같은 내용의 생각이 이미 있어요.';
    }
    final ordered = records.entries.map((e) => MapEntry(e.key == oldText ? parsed.text : e.key, e.value)).toList();
    if (inlineLinks != null) { record.inlineLinks = List.of(inlineLinks); }
    else if (parsed.text != oldText) { record.inlineLinks.clear(); }
    if (indexLabel != null) record.indexLabel = indexLabel.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (labelOnLeft != null) record.labelOnLeft = labelOnLeft;
    if (indexLabelColor != null) record.indexLabelColor = indexLabelColor;
    record.text = parsed.text;
    if (labelColor != null) record.labelColor = labelColor;
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
  void remove(String word) {
    final removed = records.remove(word);
    if (removed == null) return;
    removed.deletedAt = DateTime.now();
    trash[removed.id] = removed;
    deletionRevision++;
    notifyListeners();
  }

  final Map<String, ElementRecord> trash = {};
  final Map<String, ElementRecord> records = {};
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
    return record == null || (!record.hiddenFromSearch && !record.tags.any(hiddenSearchTags.contains));
  }
  List<String> get visibleWords => words.where(isSearchable).toList();
  void setHidden(String word, bool hidden) {
    final record = records[word];
    if (record == null) return;
    record.hiddenFromSearch = hidden;
    notifyListeners();
  }
  void setTagHidden(String tag, bool hidden) {
    if (hidden) { hiddenSearchTags.add(tag); } else { hiddenSearchTags.remove(tag); }
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
    hiddenSearchTags.clear();
    sources.clear();
  }
}

final elements = ElementStore();

Future<void> showElementMetadata(BuildContext context, String word, {VoidCallback? onSaved}) async {
  final id = elements.records[word]?.id;
  final host = context.findAncestorStateOfType<_ElementMetadataState>() ??
    (context is StatefulElement && context.state is _ElementMetadataState ? context.state as _ElementMetadataState : null);
  if (host != null) { host._navigate(word); return; }
  try { await refreshWorkspaceForRead?.call(); }
  catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('서버 변경을 확인하지 못했습니다. 기기의 자료를 표시합니다. $e'))); }
  if (!context.mounted) return;
  final record = id == null ? elements.records[word] : elements.records.values.where((r) => r.id == id).firstOrNull;
  if (record == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('다른 기기에서 삭제된 생각입니다.'))); return; }
  word = record.text;
  await showDialog<void>(
    context: context,
    builder: (_) => _ElementMetadata(word: word, onSaved: onSaved),
  );
}

class _ElementMetadata extends StatefulWidget {
  const _ElementMetadata({required this.word, this.onSaved});
  final VoidCallback? onSaved;
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
  String? _error;
  @override
  void initState() {
    super.initState();
    _word = widget.word;
    final record = elements.records[_word]!;
    _labelEditor = TextEditingController(text: record.indexLabel);
    _labelOnLeft = record.labelOnLeft; _indexLabelColor = record.indexLabelColor;
    _tags = Set.of(record.tags);
    _labelColor = record.labelColor; _closed = record.hiddenFromSearch;
    _editor = LabelTextController(record.text, record.inlineLinks)..addListener(_extractTags);
  }

  final _drafts = <String, ({String text, Set<String> tags, List<ElementBinding> links, String label, bool left, int labelColor, int? color, bool closed})>{};
  void _navigate(String word) {
    final record = elements.records[word];
    if (record == null || word == _word) return;
    _drafts[_word] = (text: _editor.text, tags: Set.of(_tags), links: List.of(_editor.bindings),
      label: _labelEditor.text, left: _labelOnLeft, labelColor: _indexLabelColor, color: _labelColor, closed: _closed);
    final draft = _drafts[word];
    _movingTags = true;
    setState(() {
      _word = word; _error = null;
      _editor.loadDocument(draft?.text ?? record.text, draft?.links ?? record.inlineLinks);
      _tags..clear()..addAll(draft?.tags ?? record.tags);
      _labelEditor.text = draft?.label ?? record.indexLabel;
      _labelOnLeft = draft?.left ?? record.labelOnLeft; _indexLabelColor = draft?.labelColor ?? record.indexLabelColor;
      _labelColor = draft == null ? record.labelColor : draft.color; _closed = draft?.closed ?? record.hiddenFromSearch;
    });
    _movingTags = false;
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
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
    final compact = TextButton.styleFrom(minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 40, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: InlineTags(key: const ValueKey('element-tags'), tags: _tags,
          onRemove: (tag) => setState(() => _tags.remove(tag)))),
        IconButton(key: const ValueKey('thought-color'), tooltip: '생각 색상 변경',
          visualDensity: VisualDensity.compact, icon: Container(width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _closed ? wordBackgroundColor(context, word, closed: true) : _labelColor == null ? wordBackgroundColor(context, word, closed: false) : Color(_labelColor!),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant))),
          onPressed: _closed ? null : () async {
            final color = await pickHashtagColor(context, '생각', _labelColor == null ? null : Color(_labelColor!), prefix: '');
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
              Padding(padding: const EdgeInsets.only(top: 8), child: TextField(key: const ValueKey('thought-label-editor'), controller: _labelEditor,
                maxLines: 1, decoration: InputDecoration(labelText: '라벨', hintText: '라벨 붙이기', isDense: true,
                  suffixIcon: IconButton(key: const ValueKey('index-label-color'), tooltip: '라벨 색상',
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
              CaretAssist(controller: _editor, focus: _editorFocus, useThoughtLabels: true, selectionAssist: true,
                words: labelAssistTargets().where((word) => word != _word).toList(), tags: {...elements.tags, ..._tags}.toList(),
                showWhenEmpty: false, enterSelectsVisible: true,
                onWord: (word) async { await insertAssistedLink(context, _editor, word); if (mounted) _editorFocus.requestFocus(); },
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
                  if (_error != null) setState(() => _error = null);
                },
              )),
              const SizedBox(height: 8),
              MergeSemantics(child: ListTile(
                dense: true, visualDensity: const VisualDensity(vertical: -3), contentPadding: EdgeInsets.zero,
                title: const Text('생각 닫기'),
                onTap: () => setState(() => _closed = !_closed),
                trailing: SizedBox(width: 44, height: 32, child: Transform.scale(scale: .8,
                  child: Switch.adaptive(value: _closed,
                    onChanged: (hidden) => setState(() => _closed = hidden)))),
              )),
              if (element.location case final location?) Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextButton.icon(onPressed: () => showLocationPreview(context, location),
                  icon: const Icon(Icons.location_on_outlined, size: 18), label: const Text('지도 보기'))),
              if (element.photos.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PhotoGallery(photos: element.photos)),
              for (final clip in element.recordings) VoicePlayer(key: ValueKey(clip.id),
                load: () => MediaStorage.read(clip.id), durationMs: clip.durationMs),
            ],
          ),
        ),
      )),
        const Divider(key: ValueKey('element-actions-divider'), height: 16, thickness: 1),
        Align(alignment: Alignment.centerRight,
          child: Text(element.createdAt.toLocal().toString().split('.').first,
            key: const ValueKey('element-created-at'), style: Theme.of(context).textTheme.bodySmall)),
      ]),
      actions: [
        FilledButton.tonal(
          style: compact,
          onPressed: () {
            final cleaned = cleanLinkedInput(_editor);
            final error = elements.update(word, cleaned.text, inlineLinks: cleaned.links, tags: {..._tags, ...cleaned.tags}, labelColor: _labelColor, hiddenFromSearch: _closed, indexLabel: _labelEditor.text, labelOnLeft: _labelOnLeft, indexLabelColor: _indexLabelColor);
            if (error != null) {
              setState(() => _error = error);
              return;
            }
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
          child: const Text('생각 삭제'),
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

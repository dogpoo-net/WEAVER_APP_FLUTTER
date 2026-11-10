import 'tag_colors.dart';
import '../capture/location_preview.dart';
import '../capture/photo_gallery.dart';
import '../capture/capture_models.dart';
import '../capture/media_storage.dart';
import '../capture/voice_player.dart';
import 'package:flutter/gestures.dart';
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
  final Set<String> connections = {};
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
  String? update(String oldText, String input, {Iterable<String>? tags, int? labelColor, bool? hiddenFromSearch, String? indexLabel, bool? labelOnLeft, int? indexLabelColor}) {
    final parsed = parseTaggedInput(input);
    if (parsed.text.isEmpty) return '생각 내용을 입력해주세요.';
    final record = records[oldText];
    if (record == null) return '이미 삭제된 생각입니다.';
    if (parsed.text != oldText && records.containsKey(parsed.text)) {
      return '같은 내용의 생각이 이미 있어요.';
    }
    records.remove(oldText);
    if (indexLabel != null) record.indexLabel = indexLabel.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (labelOnLeft != null) record.labelOnLeft = labelOnLeft;
    if (indexLabelColor != null) record.indexLabelColor = indexLabelColor;
    record.text = parsed.text;
    if (labelColor != null) record.labelColor = labelColor;
    if (hiddenFromSearch != null) record.hiddenFromSearch = hiddenFromSearch;
    record.tags
      ..clear()
      ..addAll({...parsed.tags, ...?tags});
    records[parsed.text] = record;
    if (oldText != parsed.text) {
      renameWordColor(oldText, parsed.text);
      onRenamed?.call(oldText, parsed.text);
    }
    notifyListeners();
    return null;
  }

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

  void connect(String id, Iterable<String> targets) {
    final byId = {for (final record in records.values) record.id: record};
    final source = byId[id];
    if (source == null) return;
    for (final targetId in targets) {
      final target = byId[targetId];
      if (target == null || targetId == id) continue;
      source.connections.add(targetId);
      target.connections.add(id);
    }
    notifyListeners();
  }

  void disconnect(String id, String targetId) {
    var changed = false;
    for (final record in records.values) {
      if (record.id == id) changed = record.connections.remove(targetId) || changed;
      if (record.id == targetId) changed = record.connections.remove(id) || changed;
    }
    if (changed) notifyListeners();
  }

  void remove(String word) {
    final removed = records.remove(word);
    if (removed == null) return;
    removed.deletedAt = DateTime.now();
    trash[removed.id] = removed;
    for (final record in records.values) { record.connections.remove(removed.id); }
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

Future<void> showElementMetadata(BuildContext context, String word) async {
  if (!elements.records.containsKey(word)) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ElementMetadata(word: word),
  );
}

class _ElementMetadata extends StatefulWidget {
  const _ElementMetadata({required this.word});
  final String word;
  @override
  State<_ElementMetadata> createState() => _ElementMetadataState();
}

class _ElementMetadataState extends State<_ElementMetadata> {
  late final TextEditingController _editor;
  late final TextEditingController _labelEditor;
  bool _labelOnLeft = false;
  int _indexLabelColor = 0xFFFFF59D;
  final _contentScroll = ScrollController();
  late final Set<String> _tags;
  bool _movingTags = false;
  late String _word;
  int? _labelColor;
  late bool _closed;
  final _drafts = <String, ({String text, Set<String> tags, int? color, bool closed, String label, bool left, int labelColor})>{};
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
    _editor = TextEditingController(text: record.text)..addListener(_extractTags);
  }

  void _bind(String word) {
    final record = elements.records[word];
    if (record == null || word == _word) return;
    _drafts[_word] = (text: _editor.text, tags: Set.of(_tags), color: _labelColor, closed: _closed, label: _labelEditor.text, left: _labelOnLeft, labelColor: _indexLabelColor);
    final draft = _drafts[word];
    FocusScope.of(context).unfocus();
    _movingTags = true;
    try {
      setState(() {
        _word = word; _error = null;
        _labelColor = draft == null ? record.labelColor : draft.color;
        _closed = draft?.closed ?? record.hiddenFromSearch;
        _labelEditor.text = draft?.label ?? record.indexLabel;
        _labelOnLeft = draft?.left ?? record.labelOnLeft;
        _indexLabelColor = draft?.labelColor ?? record.indexLabelColor;
        _tags..clear()..addAll(draft?.tags ?? record.tags);
        _editor.text = draft?.text ?? record.text;
      });
    } finally { _movingTags = false; }
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
  }

  void _extractTags() {
    if (_movingTags) return;
    final completed = takeCompletedParagraphTags(_editor.value);
    if (completed.tags.isEmpty) return;
    _movingTags = true;
    try {
      setState(() {
        _tags.addAll(completed.tags);
        _editor.value = completed.value;
        _error = null;
      });
    } finally { _movingTags = false; }
  }

  @override
  void dispose() {
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
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              const SizedBox(height: 8),
              TextField(key: const ValueKey('thought-label-editor'), controller: _labelEditor,
                maxLines: 1, decoration: const InputDecoration(labelText: '라벨', hintText: '생각의 제목', isDense: true)),
              Row(children: [
                IconButton(key: const ValueKey('label-left'), tooltip: '왼쪽에 붙이기', isSelected: _labelOnLeft,
                  onPressed: () => setState(() => _labelOnLeft = true), icon: const Icon(Icons.west)),
                IconButton(key: const ValueKey('label-right'), tooltip: '오른쪽에 붙이기', isSelected: !_labelOnLeft,
                  onPressed: () => setState(() => _labelOnLeft = false), icon: const Icon(Icons.east)),
                const Spacer(),
                IconButton(key: const ValueKey('index-label-color'), tooltip: '라벨 색상',
                  icon: Icon(Icons.circle, color: Color(_indexLabelColor).withValues(alpha: .6), size: 22),
                  onPressed: () async {
                    final color = await pickHashtagColor(context, '라벨', Color(_indexLabelColor), prefix: '');
                    if (color != null && mounted) setState(() => _indexLabelColor = color.toARGB32());
                  }),
              ]),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('element-editor'),
                controller: _editor,
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
              ),
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
              if (element.connections.isNotEmpty) ...[
                const Divider(key: ValueKey('element-connections-divider'), height: 24, thickness: 1),
                Text('연결', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final linked in elements.records.values.where((r) => element.connections.contains(r.id)))
                    WordBadge(word: linked.text, displayText: linked.title, onTap: () => _bind(linked.text)),
                ]),
              ],
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
            final error = elements.update(word, _editor.text, tags: _tags, labelColor: _labelColor, hiddenFromSearch: _closed, indexLabel: _labelEditor.text, labelOnLeft: _labelOnLeft, indexLabelColor: _indexLabelColor);
            if (error != null) {
              setState(() => _error = error);
              return;
            }
            Navigator.pop(context);
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
                content: const Text('휴지통으로 이동합니다. 프로젝트의 글은 유지됩니다.'),
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

class ElementText extends StatefulWidget {
  const ElementText(this.text, {super.key, this.style, this.focusOffset});
  final String text;
  final TextStyle? style;
  final int? focusOffset;
  @override
  State<ElementText> createState() => _ElementTextState();
}
class _ElementTextState extends State<ElementText> {
  final _links = <String, TapGestureRecognizer>{};
  @override
  void dispose() { for (final link in _links.values) { link.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final text = widget.text, style = widget.style;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final hit in elements.matches(text)) {
      spans.add(TextSpan(text: text.substring(cursor, hit.start)));
      if (hit.word.contains('\n') || hit.word.contains('\r')) {
        final link = _links.putIfAbsent('${hit.start}:${hit.word}', () => TapGestureRecognizer());
        link.onTap = () => showElementMetadata(context, hit.word);
        spans.add(TextSpan(text: hit.word, recognizer: link,
          style: TextStyle(color: wordColor(context, hit.word), decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted)));
      } else { spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: ElementLink(
            key: ValueKey('element-${hit.start}'),
            word: hit.word,
            style: style,
            autofocus: widget.focusOffset == hit.start,
          ),
        ),
      );
      }
      cursor = hit.end;
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

class ElementLink extends StatefulWidget {
  const ElementLink({
    super.key,
    required this.word,
    this.style,
    this.autofocus = false,
  });
  final String word;
  final TextStyle? style;
  final bool autofocus;
  @override
  State<ElementLink> createState() => _ElementLinkState();
}

class _ElementLinkState extends State<ElementLink> {
  bool _focused = false;
  void _focus(bool value) {
    setState(() => _focused = value);
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: .4);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        autofocus: widget.autofocus,
        onFocusChange: _focus,
        borderRadius: BorderRadius.circular(6),
        onTap: () => showElementMetadata(context, widget.word),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused
                  ? wordColor(context, widget.word)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            widget.word,
            style: (widget.style ?? DefaultTextStyle.of(context).style)
                .copyWith(
                  color: wordColor(context, widget.word),
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: wordBackgroundColor(context, widget.word),
                  decorationThickness: 2,
                ),
          ),
        ),
      ),
    ),
  );
}

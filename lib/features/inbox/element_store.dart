import 'package:flutter/gestures.dart';
import 'inline_tags.dart';
import 'paragraph_tag_input.dart';
import 'package:flutter/material.dart';

import 'project_page.dart';
import 'paragraph_editor.dart';
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
  bool hiddenFromSearch = false;
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
  Future<void> Function()? onProjectChanged;
  List<Paragraph> Function()? availableParagraphs;
  void Function(String oldText, String newText)? onRenamed;
  String? update(String oldText, String input, {Iterable<String>? tags}) {
    final parsed = parseTaggedInput(input);
    if (parsed.text.isEmpty) return '원소 내용을 입력해주세요.';
    final record = records[oldText];
    if (record == null) return '이미 삭제된 원소입니다.';
    if (parsed.text != oldText && records.containsKey(parsed.text)) {
      return '같은 내용의 원소가 이미 있어요.';
    }
    records.remove(oldText);
    record.text = parsed.text;
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

  void remove(String word) {
    final removed = records.remove(word);
    if (removed == null) return;
    for (final record in records.values) { record.connections.remove(removed.id); }
    notifyListeners();
  }

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
    hiddenSearchTags.clear();
    sources.clear();
  }
}

final elements = ElementStore();

void showElementMetadata(BuildContext context, String word) {
  if (!elements.records.containsKey(word)) return;
  showDialog<void>(
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
  late final Set<String> _tags;
  bool _movingTags = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final record = elements.records[widget.word]!;
    _tags = Set.of(record.tags);
    _editor = TextEditingController(text: record.text)..addListener(_extractTags);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final element = elements.records[word];
    if (element == null) return const SizedBox.shrink();
    final uses = <ElementSource, int>{};
    final together = <String, int>{};
    for (final source in elements.sources.values.expand((s) => s)) {
      if (!source.isProject) continue;
      final hits = elements.matches(source.text);
      final count = hits.where((h) => h.word == word).length;
      if (count == 0) continue;
      uses[source] = count;
      for (final other
          in hits.map((h) => h.word).toSet().where((w) => w != word)) {
        together.update(other, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final ranked = together.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AlertDialog(
      title: _tags.isEmpty ? null : InlineTags(key: const ValueKey('element-tags'), tags: _tags,
        onRemove: (tag) => setState(() => _tags.remove(tag))),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('element-editor'),
                controller: _editor,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: '원소 내용',
                  hintText: '원소 내용 #태그',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const Divider(height: 28),
              MergeSemantics(child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('검색에서 숨기기'),
                subtitle: const Text('메인과 원소 어시스트에 표시하지 않습니다.'),
                onTap: () => setState(() => elements.setHidden(word, !element.hiddenFromSearch)),
                trailing: SizedBox(width: 48, height: 40, child: Transform.scale(
                  scale: .85,
                  child: Switch.adaptive(value: element.hiddenFromSearch,
                    onChanged: (hidden) => setState(() => elements.setHidden(word, hidden))),
                )),
              )),
              if (element.connections.isNotEmpty) ...[
                Text('연결', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final linked in elements.records.values.where((r) => element.connections.contains(r.id)))
                    WordBadge(word: linked.text, onTap: () => showElementMetadata(context, linked.text)),
                ]),
                const Divider(height: 28),
              ],
              Text('생성일', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Text(element.createdAt.toLocal().toString().split('.').first),
              const Divider(height: 28),
              Text('프로젝트 사용', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Text(
                '사용 ${uses.values.fold<int>(0, (a, b) => a + b)}회 · ${uses.length}개 위치',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('독립 문단 제외', style: Theme.of(context).textTheme.bodySmall),
              const Divider(height: 28),
              Text('사용 위치', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (uses.isEmpty) const Text('사용한 프로젝트가 없어요.'),
              for (final use in uses.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${use.key.label} · ${use.value}회'),
                      if (use.key.project != null)
                        for (final hit
                            in elements
                                .matches(use.key.text)
                                .where((h) => h.word == word))
                          TextButton.icon(
                            icon: const Icon(Icons.arrow_outward, size: 16),
                            label: Text(
                              '${use.key.text.substring(0, hit.start).split(RegExp(r'[.!?。\n]')).last}$word${use.key.text.substring(hit.end).split(RegExp(r'[.!?。\n]')).first}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () {
                              final navigator = Navigator.of(context);
                              navigator.pop();
                              navigator.push(
                                MaterialPageRoute(
                                  builder: (_) => ProjectPage(
                                    project: use.key.project!,
                                    available: elements.availableParagraphs?.call() ?? const [],
                                    initialParagraph: use.key.paragraphIndex,
                                    initialOffset: hit.start,
                                    onChanged: elements.onProjectChanged,
                                  ),
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),
              const Divider(height: 28),
              Text('함께 쓰인 원소', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (ranked.isEmpty) const Text('함께 쓰인 원소가 없어요.'),
              for (final entry in ranked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      elementBadge(context, entry.key),
                      Text(
                        '${entry.value}개 프로젝트 문단',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            final error = elements.update(word, _editor.text, tags: _tags);
            if (error != null) {
              setState(() => _error = error);
              return;
            }
            Navigator.pop(context);
          },
          child: const Text('저장'),
        ),
        TextButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('원소를 삭제할까요?'),
                content: const Text('모든 원소 목록에서 삭제합니다. 문단과 프로젝트의 글은 유지됩니다.'),
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
          child: const Text('원소 삭제'),
        ),
        TextButton(
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

import 'package:flutter/material.dart';

import 'element_store.dart';
import 'workspace_storage.dart';
import 'word_badge.dart';

class TagPage extends StatefulWidget {
  const TagPage({
    super.key,
    required this.tag,
    required this.notes,
    required this.onOpen,
  });
  final String tag;
  final List<Note> notes;
  final Future<void> Function(Note) onOpen;
  @override
  State<TagPage> createState() => _TagPageState();
}

class _TagPageState extends State<TagPage> {
  @override
  Widget build(BuildContext context) {
    final words = elements.records.values
        .where((r) => r.tags.contains(widget.tag))
        .map((r) => r.text)
        .toSet();
    final related = widget.notes
        .where(
          (n) =>
              (n.paragraphs != null || n.project != null) &&
              (n.tags.contains(widget.tag) || elements
                  .matches(
                    n.project?.paragraphs.map((p) => p.text).join('\n') ??
                        n.content,
                  )
                  .any((hit) => words.contains(hit.word))),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '원소 ${words.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: words
                      .map(
                        (word) => WordBadge(
                          word: word,
                          onTap: () => showElementMetadata(context, word),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 32),
                for (final isProject in [false, true]) ...[
                  Text('${isProject ? '프로젝트' : '문단'} ${related.where((n) => (n.project != null) == isProject).length}',
                    key: ValueKey(isProject ? 'tag-projects' : 'tag-paragraphs'),
                    style: Theme.of(context).textTheme.titleMedium),
                  if (!related.any((n) => (n.project != null) == isProject))
                    Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(isProject ? '관련 프로젝트가 없어요.' : '관련 문단이 없어요.')),
                  for (final note in related.where((n) => (n.project != null) == isProject))
                    ListTile(title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () async { await widget.onOpen(note); if (mounted) setState(() {}); }),
                  if (!isProject) const Divider(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

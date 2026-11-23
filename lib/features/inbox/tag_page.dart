import 'tag_colors.dart';
import 'overview_collections.dart';
import 'workspace_routes.dart';
import 'desktop_menu_frame.dart';

import 'package:flutter/material.dart';

import 'element_store.dart';
import 'workspace_storage.dart';
import 'word_badge.dart';

class TagListPage extends StatefulWidget {
  const TagListPage({
    super.key,
    required this.tags,
    this.onColorChanged,
    required this.notes,
    required this.onOpen,
  });

  final VoidCallback? onColorChanged;
  final List<String> Function() tags;
  final List<Note> notes;
  final Future<void> Function(Note) onOpen;

  @override
  State<TagListPage> createState() => _TagListPageState();
}

class _TagListPageState extends State<TagListPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) => DesktopMenuFrame(
    child: Scaffold(
      appBar: AppBar(
        title: const WorkspaceTitle('해시태그'),
        actions: const [DesktopMenuAction()],
      ),
      body: DesktopMenuBody(
        child: ListenableBuilder(
          listenable: elements,
          builder: (context, _) {
            final names = widget
                .tags()
                .where((tag) => tag.toLowerCase().contains(_query))
                .toList();
            final counts = <String, int>{};
            for (final thought in elements.records.values) {
              for (final tag in thought.tags) {
                counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
              }
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: TextField(
                    style: TextStyle(
                      fontSize: MediaQuery.sizeOf(context).width < 1000
                          ? 13
                          : 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: '해시태그 찾기',
                      prefixIcon: Icon(Icons.search, size: 18),
                      prefixIconConstraints: BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(
                      () => _query = value
                          .trim()
                          .replaceFirst(RegExp(r'^#+'), '')
                          .trim()
                          .toLowerCase(),
                    ),
                  ),
                ),
                OverviewItemCount('해시태그 ${names.length}개'),
                Expanded(
                  child: names.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty ? '해시태그가 없습니다.' : '일치하는 해시태그가 없습니다.',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: names.length,
                          itemBuilder: (context, index) {
                            final name = names[index];
                            final color = Color(hashtagColors[name] ?? 0xFF90A4AE);
                            return ListTile(
                              trailing: IconButton(
                                tooltip: '#$name 색상 변경',
                                icon: Icon(Icons.circle, color: color, size: 18),
                                onPressed: widget.onColorChanged == null ? null : () async {
                                  final next = await pickHashtagColor(context, name, color);
                                  if (!mounted || next == null || !widget.tags().contains(name)) return;
                                  hashtagColors[name] = next.toARGB32();
                                  elements.refreshVisibility();
                                  widget.onColorChanged?.call();
                                },
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '#$name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${counts[name] ?? 0}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TagPage(
                                    tag: name,
                                    notes: widget.notes,
                                    onOpen: widget.onOpen,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

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
  void _refresh() { if(mounted)setState((){}); }
  @override
  void initState() { super.initState();elements.addListener(_refresh); }
  @override
  void dispose() { elements.removeListener(_refresh);super.dispose(); }
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
              (n.tags.contains(widget.tag) || (n.project?.tags.contains(widget.tag) ?? false) || elements
                  .matches(
                    n.project?.content ??
                        n.content,
                  )
                  .any((hit) => words.contains(hit.word))),
        )
        .toList();
    return DesktopMenuFrame(child: Scaffold(
      appBar: AppBar(centerTitle: false, titleSpacing: 0, leadingWidth: 44, title: WorkspaceTitle('#${widget.tag}'), actions: [const DesktopMenuAction()]),
      body: DesktopMenuBody(child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '생각 ${words.length}',
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
                Text('문서 ${related.where((n) => n.project != null).length}',
                  key: const ValueKey('tag-projects'), style: Theme.of(context).textTheme.titleMedium),
                if (!related.any((n) => n.project != null))
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('관련 문서가 없어요.')),
                for (final note in related.where((n) => n.project != null))
                  ListTile(title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () async { await widget.onOpen(note); if (mounted) setState(() {}); }),
              ],
            ),
          ),
        ),
      )),
    ));
  }
}

import 'element_store.dart';
import 'workspace_storage.dart';

/// Count occurrences in saved paragraphs/project sentences, not element creation.
/// Co-occurrence counts each shared sentence once, even with repeated words.
class ElementUsage {
  ElementUsage._(this.counts, this.together);
  final Map<String, int> counts;
  final Map<String, Map<String, int>> together;

  factory ElementUsage.fromNotes(Iterable<Note> notes, ElementStore store) {
    final counts = {for (final word in store.words) word: 0};
    final together = {for (final word in store.words) word: <String, int>{}};
    for (final note in notes) {
      final texts = note.project?.document != null ? [note.project!.document!]
        : (note.project?.paragraphs ?? note.paragraphs)?.map((p) => p.text).toList();
      if (texts == null) continue;
      for (final text in texts) {
        final hits = store.matches(text);
        for (final hit in hits) { counts.update(hit.word, (count) => count + 1); }
        final unique = hits.map((hit) => hit.word).toSet();
        for (final word in unique) {
          for (final other in unique.where((other) => other != word)) {
            together[word]!.update(other, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    return ElementUsage._(counts, together);
  }
}

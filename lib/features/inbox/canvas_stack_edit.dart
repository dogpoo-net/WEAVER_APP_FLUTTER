import 'dart:ui';
import 'canvas_geometry.dart';

bool canDockThought(Rect moving, Rect target) =>
    moving.left < target.right && moving.right > target.left &&
    moving.bottom >= target.top && moving.top < target.bottom;

/// Collapse missing whole stack slots while retaining fractional resize offsets.
void closeStackHoles(Map<String, Offset> positions, Iterable<String> members) {
  final ordered = members.where(positions.containsKey).toList()
    ..sort((a, b) => positions[a]!.dy.compareTo(positions[b]!.dy));
  var shift = 0.0;
  for (var i = 1; i < ordered.length; i++) {
    final point = positions[ordered[i]]!;
    final previous = positions[ordered[i - 1]]!;
    final gap = point.dy - shift - previous.dy;
    final slots = (gap / 32).round();
    if (slots > 1 && (gap - slots * 32).abs() < .5) shift += (slots - 1) * 32;
    positions[ordered[i]] = point.translate(0, -shift);
  }
}

/// Close only slots vacated by an edit, never normalize unrelated arrangements.
void closeVacatedStackSlots(Map<String, Offset> positions,
    Map<String, Offset> before, Set<String> removed, {Map<String,String> groups = const {}}) {
  final visited = <String>{};
  for (final id in removed) {
    if (!before.containsKey(id) || visited.contains(id)) continue;
    final group = alignedStackMembers(id, before,groups:groups).toList()
      ..sort((a, b) => before[a]!.dy.compareTo(before[b]!.dy));
    visited.addAll(group);
    var gaps = 0;
    for (final member in group) {
      if (removed.contains(member)) { gaps++; continue; }
      if (gaps > 0 && positions[member] == before[member]) {
        positions[member] = before[group[group.indexOf(member)-gaps]]!;
      }
    }
    closeStackHoles(positions, group.where((member) => !removed.contains(member)));
  }
}

/// Midpoint of the longest exposed segment of the facing vertical border.
/// Return null when that entire border is covered.
Offset? exposedSideAnchor(Rect card, Iterable<Rect> above, Offset target) {
  final x = target.dx < card.center.dx ? card.left : card.right;
  var segments = <(double, double)>[(card.top, card.bottom)];
  for (final cover in above) {
    if (cover.left > x || cover.right < x) continue;
    final next = <(double, double)>[];
    for (final (top, bottom) in segments) {
      if (cover.bottom <= top || cover.top >= bottom) { next.add((top, bottom)); continue; }
      if (cover.top > top) next.add((top, cover.top));
      if (cover.bottom < bottom) next.add((cover.bottom, bottom));
    }
    segments = next;
  }
  if (segments.isEmpty) return null;
  segments.sort((a, b) => (b.$2-b.$1).compareTo(a.$2-a.$1));
  return Offset(x, (segments.first.$1 + segments.first.$2) / 2);
}

/// Only obscured cards need side ports. A tag above/below the card's horizontal
/// span uses the original center port, avoiding an awkward vertical side edge.
Offset? hashtagConnectionAnchor(Rect card, Iterable<Rect> above, Offset target) {
  final covers = above.where(card.overlaps).toList();
  if (covers.isEmpty || (target.dx >= card.left && target.dx <= card.right)) {
    return card.center;
  }
  return exposedSideAnchor(card, covers, target);
}

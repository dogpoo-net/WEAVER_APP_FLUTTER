import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// Lay out selected bounds from their upper-left corner in reading order.
Map<String, Offset> arrangeCanvasSelection(Map<String, Rect> bounds, {required bool stack}) {
  if (bounds.isEmpty) return {};
  final ids = bounds.keys.toList()..sort((a, b) {
    final vertical = bounds[a]!.top.compareTo(bounds[b]!.top);
    return vertical != 0 ? vertical : a.compareTo(b);
  });
  final ordered = <String>[];
  for (var start = 0; start < ids.length;) {
    var end = start + 1;
    // Slightly staggered cards still read as one row. Stack slots are 32 apart.
    while (end < ids.length && bounds[ids[end]]!.top - bounds[ids[start]]!.top <= 16) {
      end++;
    }
    final row = ids.sublist(start, end)..sort((a, b) {
      final horizontal = bounds[a]!.left.compareTo(bounds[b]!.left);
      return horizontal != 0 ? horizontal : a.compareTo(b);
    });
    ordered.addAll(row);
    start = end;
  }
  final origin = Offset(bounds.values.map((r) => r.left).reduce(math.min),
      bounds[ids.first]!.top);
  final columns = math.sqrt(ids.length).round();
  final strideX = bounds.values.map((r) => r.width).reduce(math.max) + 16;
  final strideY = bounds.values.map((r) => r.height).reduce(math.max) + 16;
  return {
    for (var i = 0; i < ordered.length; i++)
      ordered[i]: origin + (stack ? Offset(0, i * 32.0)
          : Offset((i % columns) * strideX, (i ~/ columns) * strideY)),
  };
}

/// Find the shortest free translation along sampled directions, keeping the
/// stationary boxes fixed. Collision intervals are merged along each ray.
Offset releaseBox(Rect moving, List<Rect> obstacles, {double gap = 24}) {
  // A stationary box already outside every collision interval has a zero-cost
  // solution. Leave near-touching and out-of-bounds cases to the ray solver.
  if (moving.left >= 32 && moving.top >= 32) {
    final padded = moving.inflate(gap + .01);
    final needsRelease = obstacles.any(padded.overlaps);
    if (!needsRelease) return Offset.zero;
  }

  Offset? best, bestLocal;
  for (var i = 0; i < 128; i++) {
    final angle = i * math.pi * 2 / 128;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final intervals = <(double, double)>[];
    for (final other in obstacles) {
      double start, end;
      final relative = moving.center - other.center;
      final half = Offset((moving.width + other.width) / 2 + gap, (moving.height + other.height) / 2 + gap);
      start = double.negativeInfinity; end = double.infinity;
      var misses = false;
      for (final axis in [(relative.dx, direction.dx, half.dx), (relative.dy, direction.dy, half.dy)]) {
        if (axis.$2.abs() < 1e-8) {
          if (axis.$1.abs() >= axis.$3) misses = true;
        } else {
          final a = (-axis.$3 - axis.$1) / axis.$2;
          final b = (axis.$3 - axis.$1) / axis.$2;
          start = math.max(start, math.min(a, b));
          end = math.min(end, math.max(a, b));
        }
      }
      if (misses || start >= end) continue;
      if (end >= 0) intervals.add((start, end));
    }
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var distance = 0.0;
    for (final interval in intervals) {
      if (interval.$1 > distance) break;
      if (interval.$2 >= distance) distance = interval.$2 + .01;
    }
    final shift = direction * distance;
    final result = moving.shift(shift);
    if (result.left < 32 || result.top < 32) continue;
    if (best == null || shift.distanceSquared < best.distanceSquared) best = shift;
    // Prefer escaping existing overlap without crossing a previously clear box.
    final crossesNeighbor = intervals.any((interval) => interval.$1 > 0 && interval.$1 < distance);
    if (!crossesNeighbor && (bestLocal == null || shift.distanceSquared < bestLocal.distanceSquared)) bestLocal = shift;
  }
  return bestLocal ?? best ?? Offset.zero;
}

/// Align a card near a stacked position, without changing its box membership.
Offset snapThought(Rect moving, Iterable<Rect> others, {double tolerance = 24}) {
  var best = Offset.zero;
  var nearest = tolerance * tolerance;
  for (final other in others) {
    if (!moving.inflate(tolerance).overlaps(other)) continue;
    for (final y in [other.top - 32, other.top + 32]) {
      final delta = Offset(other.left - moving.left, y - moving.top);
      if (delta.distanceSquared < nearest) { nearest = delta.distanceSquared; best = delta; }
    }
  }
  return best;
}

void moveThoughtLayers(List<String> order, Set<String> selected, {required bool up}) {
  if (up) {
    for (var i = order.length - 2; i >= 0; i--) {
      if (selected.contains(order[i]) && !selected.contains(order[i + 1])) {
        final id = order[i]; order[i] = order[i + 1]; order[i + 1] = id;
      }
    }
  } else {
    for (var i = 1; i < order.length; i++) {
      if (selected.contains(order[i]) && !selected.contains(order[i - 1])) {
        final id = order[i]; order[i] = order[i - 1]; order[i - 1] = id;
      }
    }
  }
}

/// Cross the nearest visible overlapping card, or the next visible layer
/// when there is no overlap in the requested direction.
void stepCanvasLayers(
  List<String> layers,
  Map<String, Offset> positions,
  Set<String> selected, {
  required bool up,
  required Map<String, String> groups,
  Map<String, Rect>? bounds,
  Set<String> photos = const {},
}) {
  final visible = layers.where((id) => bounds == null || bounds.containsKey(id)).toList();
  final stackPositions = Map<String, Offset>.of(positions)
    ..removeWhere((id, _) => photos.contains(id));
  final loose = Set<String>.of(selected);
  for (final id in selected) {
    if (!loose.contains(id) || !stackPositions.containsKey(id)) continue;
    final stack = alignedStackMembers(id, stackPositions, groups: groups);
    if (stack.length < 2) continue;
    loose.removeAll(stack);
    final slots = visible.where(stack.contains).toList()
      ..sort((a, b) => positions[a]!.dy.compareTo(positions[b]!.dy));
    final reordered = List<String>.of(slots);
    moveThoughtLayers(reordered, selected, up: !up);
    if (listEquals(reordered, slots)) continue;
    final points = slots.map((member) => positions[member]!).toList();
    var index = 0;
    for (var i = 0; i < visible.length; i++) {
      if (!stack.contains(visible[i])) continue;
      visible[i] = reordered[index];
      positions[reordered[index]] = points[index];
      index++;
    }
  }
  final order = up ? visible : visible.reversed.toList();
  for (final id in order.where(loose.contains).toList().reversed) {
    final start = order.indexOf(id);
    var target = start;
    for (var i = start + 1; i < order.length; i++) {
      final other = order[i];
      if (selected.contains(other)) break;
      if (target == start) target = i;
      if (bounds == null || bounds[id]!.overlaps(bounds[other]!)) {
        target = i;
        break;
      }
    }
    order.removeAt(start);
    order.insert(target, id);
  }
  final moved = (up ? order : order.reversed).iterator;
  for (var i = 0; i < layers.length; i++) {
    if (bounds == null || bounds.containsKey(layers[i])) {
      moved.moveNext();
      layers[i] = moved.current;
    }
  }

}

void reverseThoughtLayers(List<String> order, Set<String> selected) {
  final reversed = order.where(selected.contains).toList().reversed.iterator;
  for (var i = 0; i < order.length; i++) {
    if (selected.contains(order[i])) { reversed.moveNext(); order[i] = reversed.current; }
  }
}

/// Use remembered groups after resizing; legacy layouts use exact stack slots.
void reorderStackPositions(Map<String, Offset> positions, Set<String> selected, {bool? up, Map<String,String> groups = const {}}) {
  final remaining = positions.keys.toSet();
  while (remaining.isNotEmpty) {
    final group = alignedStackMembers(remaining.first, positions, groups: groups).toList();
    remaining.removeAll(group);
    if (group.length < 2 || !group.any(selected.contains)) continue;
    group.sort((a, b) => positions[a]!.dy.compareTo(positions[b]!.dy));
    if (up == null) {
      final chosen = group.where(selected.contains).toList();
      final slots = chosen.map((id) => positions[id]!).toList().reversed.toList();
      for (var i = 0; i < chosen.length; i++) { positions[chosen[i]] = slots[i]; }
    } else {
      final slots = group.map((id) => positions[id]!).toList();
      final reordered = [...group];
      moveThoughtLayers(reordered, selected, up: !up);
      for (var i = 0; i < reordered.length; i++) { positions[reordered[i]] = slots[i]; }
    }
  }
}

Offset nextStackSlot(String target, String moving, Map<String, Offset> positions) {
  var slot = positions[target]! + const Offset(0, 32);
  while (positions.entries.any((e) => e.key != moving && (e.value - slot).distance < .5)) {
    slot += const Offset(0, 32);
  }
  return slot;
}

Path visibleThoughtPath(Rect card, Iterable<Rect> above, {double radius = 6}) {
  var path = Path()..addRRect(RRect.fromRectAndRadius(card, Radius.circular(radius)));
  for (final cover in above) {
    if (!card.overlaps(cover)) continue;
    path = Path.combine(PathOperation.difference, path,
      Path()..addRRect(RRect.fromRectAndRadius(cover, Radius.circular(radius))));
  }
  return path;
}

bool selectsVisibleThought(Rect selection, Rect card, Iterable<Rect> above, {double radius = 6}) {
  if (!selection.overlaps(card)) return false;
  final intersection = Path.combine(PathOperation.intersect,
    visibleThoughtPath(card, above, radius: radius), Path()..addRect(selection));
  return intersection.computeMetrics().isNotEmpty;
}

double snapStackWidth(double width, Iterable<double> neighbors, {double tolerance = 16}) {
  var result = width, distance = tolerance;
  for (final candidate in neighbors) {
    final delta = (candidate - width).abs();
    if (delta <= distance) { result = candidate; distance = delta; }
  }
  return result;
}

/// Remembered membership, or exact aligned slots for unmigrated cards.
Set<String> alignedStackMembers(String seed, Map<String, Offset> positions, {Map<String,String> groups = const {}}) {
  if(groups.containsKey(seed))return positions.keys.where((id)=>groups[id]==groups[seed]).toSet();
  final group = <String>{seed};
  final queue = <String>[seed];
  for (var i = 0; i < queue.length; i++) {
    final p = positions[queue[i]];
    if (p == null) continue;
    for (final e in positions.entries) {
      if (!groups.containsKey(e.key) && !group.contains(e.key) && (e.value.dx - p.dx).abs() < .5 &&
          ((e.value.dy - p.dy).abs() - 32).abs() < .5) {
        group.add(e.key); queue.add(e.key);
      }
    }
  }
  return group;
}

/// Only top and left are fixed; the scene grows to the right and bottom.
class CanvasBoundaryPainter extends CustomPainter {
  const CanvasBoundaryPainter(this.color,{this.scale=1});
  final Color color;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final zoom=scale.isFinite && scale>0?scale:1.0;
    final dash=6/zoom,step=12/zoom;
    final paint = Paint()..color = color..strokeWidth = 1/zoom;
    for (var x = 32.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 32), Offset(math.min(x + dash, size.width), 32), paint);
    }
    for (var y = 32.0; y < size.height; y += step) {
      canvas.drawLine(Offset(32, y), Offset(32, math.min(y + dash, size.height)), paint);
    }
  }
  @override
  bool shouldRepaint(CanvasBoundaryPainter oldDelegate) => oldDelegate.color != color || oldDelegate.scale != scale;
}

/// Keep a stack's paint order consistent with its vertical slots. Unrelated
/// cards retain their layer slots, even when interleaved with stack members.
void alignStackLayers(List<String> layers, Map<String, Offset> positions,
    Map<String, String> groups) {
  final remaining = positions.keys.toSet();
  while (remaining.isNotEmpty) {
    final group = alignedStackMembers(remaining.first, positions, groups: groups);
    remaining.removeAll(group);
    final ordered = layers.where(group.contains).toList()
      ..sort((a, b) => positions[a]!.dy.compareTo(positions[b]!.dy));
    var index = 0;
    for (var i = 0; i < layers.length; i++) {
      if (group.contains(layers[i])) layers[i] = ordered[index++];
    }
  }
}

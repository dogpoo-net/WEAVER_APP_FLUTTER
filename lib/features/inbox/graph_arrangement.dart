import 'dart:math' as math;
import 'package:flutter/material.dart';

const graphThoughtSize = Size(170, 96);
const graphTagSize = Size(178, 48);
const _columns = 6;
const _pitchX = 250.0;
const _originX = 640.0;

Rect thoughtBounds(Offset p) => p & graphThoughtSize;
Rect tagBounds(Offset center) => Rect.fromCenter(center: center, width: graphTagSize.width, height: graphTagSize.height);

/// Allocate only missing nodes. Existing/manual positions and filtered nodes stay put.
void arrangeGraph({required List<String> thoughts, required List<String> tags,
  required Map<String, Offset> positions, required Map<String, Offset> tagPositions, Map<String, Size> sizes = const {}}) {
  final occupied = <Rect>[
    ...positions.entries.map((e) => e.value & (sizes[e.key] ?? graphThoughtSize)), ...tagPositions.values.map(tagBounds),
  ];
  bool free(Rect candidate) => !occupied.any((r) => r.inflate(12).overlaps(candidate));
  final tagRows = math.max(1, (tags.length / _columns).ceil());
  var tagSlot = 0;
  for (final tag in tags) {
    final id = 'tag:$tag';
    if (tagPositions.containsKey(id)) continue;
    while (true) {
      // Extend to the right when all original rows are occupied, keeping new tags above thoughts.
      final column = tagSlot % _columns + (tagSlot ~/ (_columns * tagRows)) * _columns;
      final row = (tagSlot ~/ _columns) % tagRows;
      tagSlot++;
      final p = Offset(_originX + column * _pitchX, 160 + row * 100.0);
      final rect = p & graphTagSize;
      if (!free(rect)) continue;
      tagPositions[id] = rect.center; occupied.add(rect); break;
    }
  }
  final bottom = tagPositions.values.map((p) => tagBounds(p).bottom).fold(160.0, math.max);
  final thoughtTop = bottom + 100;
  var slot = 0;
  for (final id in thoughts) {
    if (positions.containsKey(id)) continue;
    while (true) {
      final p = Offset(_originX + (slot % _columns) * _pitchX, thoughtTop + (slot ~/ _columns) * 160);
      slot++;
      final rect = thoughtBounds(p);
      if (!free(rect)) continue;
      positions[id] = p; occupied.add(rect); break;
    }
  }
}

/// Routes through empty corridors; computed on geometry changes, never by a timer.
class GraphEdgeRouter {
  GraphEdgeRouter(this.nodes) {
    for (final entry in nodes.entries) {
      final r = entry.value;
      for (var x = (r.left / _cell).floor(); x <= (r.right / _cell).floor(); x++) {
        for (var y = (r.top / _cell).floor(); y <= (r.bottom / _cell).floor(); y++) {
          (_cells[(x, y)] ??= <String>{}).add(entry.key);
        }
      }
    }
    _left = nodes.values.map((r) => r.left).fold(double.infinity, math.min);
    _right = nodes.values.map((r) => r.right).fold(double.negativeInfinity, math.max);
  }
  final Map<String, Rect> nodes;
  static const _cell = 250.0;
  final _cells = <(int, int), Set<String>>{};
  late final double _left, _right;

  bool _clear(Offset a, Offset b) {
    if ((a - b).distanceSquared < .001) return true;
    final bounds = Rect.fromPoints(a, b).inflate(.01);
    final checked = <String>{};
    for (var x = (bounds.left / _cell).floor(); x <= (bounds.right / _cell).floor(); x++) {
      for (var y = (bounds.top / _cell).floor(); y <= (bounds.bottom / _cell).floor(); y++) {
        for (final id in _cells[(x, y)] ?? const <String>{}) {
          if (!checked.add(id)) continue;
          final r = nodes[id]!.deflate(.1);
          if (a.dx == b.dx) {
            if (a.dx > r.left && a.dx < r.right && math.max(a.dy, b.dy) > r.top && math.min(a.dy, b.dy) < r.bottom) return false;
          } else {
            if (a.dy > r.top && a.dy < r.bottom && math.max(a.dx, b.dx) > r.left && math.min(a.dx, b.dx) < r.right) return false;
          }
        }
      }
    }
    return true;
  }

  List<Offset> route(String from, String to, int lane) {
    final a = nodes[from]!, b = nodes[to]!;
    final gap = 14.0 + (lane % 6) * 3;
    final port = ((lane % 7) - 3) * 7.0;
    final candidates = <List<Offset>>[];
    if ((a.center.dy - b.center.dy).abs() < .01) {
      candidates.add(a.center.dx < b.center.dx
        ? [a.centerRight, b.centerLeft] : [a.centerLeft, b.centerRight]);
    }
    for (final aTop in [false, true]) {
      for (final bTop in [true, false]) {
        final start = Offset(a.center.dx + port, aTop ? a.top : a.bottom);
        final end = Offset(b.center.dx - port, bTop ? b.top : b.bottom);
        final ay = start.dy + (aTop ? -gap : gap), by = end.dy + (bTop ? -gap : gap);
        for (final x in {a.right + gap, a.left - gap, b.right + gap, b.left - gap, _left - gap, _right + gap}) {
          candidates.add([start, Offset(start.dx, ay), Offset(x, ay), Offset(x, by), Offset(end.dx, by), end]);
        }
      }
    }
    double length(List<Offset> points) {
      var total = 0.0;
      for (var i = 1; i < points.length; i++) { total += (points[i] - points[i - 1]).distance; }
      return total;
    }
    candidates.sort((a, b) => length(a).compareTo(length(b)));
    for (final points in candidates) {
      var clear = true;
      for (var i = 1; i < points.length; i++) {
        if (!_clear(points[i - 1], points[i])) { clear = false; break; }
      }
      if (clear) return points;
    }
    // Overlapping manually dragged nodes have no unobstructed route.
    return [a.center, b.center];
  }
}

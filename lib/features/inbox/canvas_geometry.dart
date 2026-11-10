import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Find the shortest free translation along sampled directions, keeping the
/// stationary boxes fixed. Collision intervals are merged along each ray.
Offset releaseBox(Rect moving, List<Rect> obstacles, {required bool rectangular, double gap = 24}) {
  Offset? best;
  for (var i = 0; i < 128; i++) {
    final angle = i * math.pi * 2 / 128;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final intervals = <(double, double)>[];
    for (final other in obstacles) {
      double start, end;
      final relative = moving.center - other.center;
      if (rectangular) {
        final half = Offset((moving.width + other.width) / 2 + gap, (moving.height + other.height) / 2 + gap);
        start = double.negativeInfinity; end = double.infinity;
        var misses = false;
        for (final axis in [(relative.dx, direction.dx, half.dx), (relative.dy, direction.dy, half.dy)]) {
          if (axis.$2.abs() < 1e-8) {
            if (axis.$1.abs() >= axis.$3) misses = true;
          } else {
            final a = (-axis.$3 - axis.$1) / axis.$2, b = (axis.$3 - axis.$1) / axis.$2;
            start = math.max(start, math.min(a, b)); end = math.min(end, math.max(a, b));
          }
        }
        if (misses || start >= end) continue;
      } else {
        final radius = (moving.width + other.width) / 2 + gap;
        final projection = relative.dx * direction.dx + relative.dy * direction.dy;
        final discriminant = projection * projection - relative.distanceSquared + radius * radius;
        if (discriminant <= 0) continue;
        start = -projection - math.sqrt(discriminant); end = -projection + math.sqrt(discriminant);
      }
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
  }
  return best ?? Offset.zero;
}

/// Align a card near a stacked position, without changing its box membership.
Offset snapThought(Rect moving, Iterable<Rect> others, {double tolerance = 16}) {
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

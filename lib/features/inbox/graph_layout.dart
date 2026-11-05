import 'dart:convert';
import 'package:flutter/material.dart';

/// Each graph owns its layout; thought IDs survive text edits.
class GraphLayout {
  final positions = <String, Offset>{};
  final sizes = <String, Offset>{};
  final tags = <String, Offset>{};
  List<double>? viewport;
  String query = '';
  bool unlinkedOnly = false;

  void copyFrom(GraphLayout other) {
    positions..clear()..addAll(other.positions);
    sizes..clear()..addAll(other.sizes);
    tags..clear()..addAll(other.tags);
    viewport = other.viewport?.toList();
    query = other.query;
    unlinkedOnly = other.unlinkedOnly;
  }

  Map<String, dynamic> toJson() => {
    'positions': {for (final e in positions.entries) e.key: [e.value.dx, e.value.dy]},
    'tags': {for (final e in tags.entries) e.key: [e.value.dx, e.value.dy]},
    'sizes': {for (final e in sizes.entries) e.key: [e.value.dx, e.value.dy]},
    'viewport': viewport,
    'query': query,
    'unlinkedOnly': unlinkedOnly,
  };

  static GraphLayout fromJson(dynamic data) {
    final layout = GraphLayout();
    if (data is! Map) return layout;
    void readPoints(dynamic source, Map<String, Offset> target) {
      if (source is! Map) return;
      for (final e in source.entries) {
        final v = e.value;
        if (e.key is String && v is List && v.length == 2 &&
            v.every((n) => n is num && n.isFinite)) {
          target[e.key as String] = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
        }
      }
    }
    readPoints(data['positions'], layout.positions);
    readPoints(data['tags'], layout.tags);
    readPoints(data['sizes'], layout.sizes);
    layout.sizes.updateAll((id, p) => Offset(p.dx.clamp(178, 640), p.dy.clamp(84, 520)));
    final matrix = data['viewport'];
    if (matrix is List && matrix.length == 16 && matrix.every((n) => n is num && n.isFinite)) {
      final values = matrix.map((n) => (n as num).toDouble()).toList();
      // Only accept InteractiveViewer's uniform scale and translation matrix.
      if (values[0] >= .15 && values[0] <= 2.5 && values[5] == values[0] &&
          values[10] > 0 && values[15] == 1 &&
          [1, 2, 3, 4, 6, 7, 8, 9, 11, 14].every((i) => values[i] == 0)) {
        layout.viewport = values;
      }
    }
    if (data['query'] is String) layout.query = data['query'] as String;
    layout.unlinkedOnly = data['unlinkedOnly'] == true;
    return layout;
  }
}

GraphLayout pageGraphLayout = GraphLayout();

String encodeGraphLayouts(Map<String, GraphLayout> boxes) => jsonEncode({
  'page': pageGraphLayout.toJson(),
  'boxes': {for (final e in boxes.entries) e.key: e.value.toJson()},
});

void restoreGraphLayouts(String raw, Map<String, GraphLayout> boxes) {
  final data = jsonDecode(raw);
  if (data is! Map) return;
  if (data['page'] is Map) pageGraphLayout.copyFrom(GraphLayout.fromJson(data['page']));
  final savedBoxes = data['boxes'];
  if (savedBoxes is Map) {
    for (final e in boxes.entries) {
      if (savedBoxes[e.key] is Map) e.value.copyFrom(GraphLayout.fromJson(savedBoxes[e.key]));
    }
  }
}

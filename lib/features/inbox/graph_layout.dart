import 'dart:convert';
import 'package:flutter/material.dart';

/// Each graph owns its layout; thought IDs survive text edits.
class GraphLayout {
  GraphLayout? _blocks;
  GraphLayout get blockLayout => _blocks ??= GraphLayout();
  final layers = <String>[];
  final positions = <String, Offset>{};
  final sizes = <String, Offset>{};
  final tags = <String, Offset>{};
  final folderPositions = <String, Offset>{};
  List<double>? viewport;
  String query = '';
  bool hideTags = false;
  bool stacked = false;

  void copyFrom(GraphLayout other, {bool includeBlocks=true}) {
    if(includeBlocks){if(other._blocks!=null){blockLayout.copyFrom(other._blocks!);}else{_blocks=null;}}
    layers..clear()..addAll(other.layers);
    positions..clear()..addAll(other.positions);
    sizes..clear()..addAll(other.sizes);
    tags..clear()..addAll(other.tags);
    folderPositions..clear()..addAll(other.folderPositions);
    viewport = other.viewport?.toList();
    query = other.query;
    hideTags = other.hideTags;
    stacked = other.stacked;
  }

  Map<String, dynamic> toJson() => {
    if (_blocks != null) 'blocks': _blocks!.toJson(),
    'positions': {for (final e in positions.entries) e.key: [e.value.dx, e.value.dy]},
    'tags': {for (final e in tags.entries) e.key: [e.value.dx, e.value.dy]},
    'sizes': {for (final e in sizes.entries) e.key: [e.value.dx, e.value.dy]},
    'folderPositions': {for (final e in folderPositions.entries) e.key: [e.value.dx, e.value.dy]},
    'viewport': viewport,
    'query': query,
    'hideTags': hideTags,
    'stacked': stacked,
    'layers': layers,
  };

  static GraphLayout fromJson(dynamic data) {
    final layout = GraphLayout();
    if (data is! Map) return layout;
    if (data['layers'] is List) layout.layers.addAll((data['layers'] as List).whereType<String>().toSet());
    if (data['blocks'] is Map) layout._blocks = GraphLayout.fromJson(data['blocks']);
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
    readPoints(data['folderPositions'], layout.folderPositions);
    layout.sizes.updateAll((id, p) => Offset(p.dx.clamp(170, 640), p.dy.clamp(76, 520)));
    final matrix = data['viewport'];
    if (matrix is List && matrix.length == 16 && matrix.every((n) => n is num && n.isFinite)) {
      final values = matrix.map((n) => (n as num).toDouble()).toList();
      // Only accept InteractiveViewer's uniform scale and translation matrix.
      if (values[0] >= .15 && values[0] <= 12 && values[5] == values[0] &&
          values[10] > 0 && values[15] == 1 &&
          [1, 2, 3, 4, 6, 7, 8, 9, 11, 14].every((i) => values[i] == 0)) {
        layout.viewport = values;
      }
    }
    if (data['query'] is String) layout.query = data['query'] as String;
    layout.hideTags = data['hideTags'] == true;
    layout.stacked = data['stacked'] == true;
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

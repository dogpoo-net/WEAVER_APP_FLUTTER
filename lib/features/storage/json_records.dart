import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A lossless JSON tree whose record values are stored independently.
/// Array order and empty maps/lists are retained in the manifest.
class JsonRecords {
  JsonRecords(this.tree, this.records);
  final Object? tree;
  final Map<String, String> records;
  static JsonRecords split(
    String raw, {
    String? Function(String, String)? reuse,
  }) => splitValue(jsonDecode(raw), reuse: reuse);
  static JsonRecords splitValue(
    Object? value, {
    String? Function(String, String)? reuse,
  }) {
    final records = <String, String>{};
    Object leaf(Object? value, List<String> path) {
      final encoded = jsonEncode(value);
      final identity = base64Url.encode(utf8.encode(jsonEncode(path)));
      final ref =
          reuse?.call(identity, encoded) ??
          '$identity.${sha256.convert(utf8.encode(encoded))}';
      records[ref] = encoded;
      return ['r', ref];
    }

    Object node(Object? value, List<String> path, {bool record = false}) {
      if (value is Map &&
          ((record && !value.containsKey('layout')) ||
              (value.containsKey('kind') &&
                  value.containsKey('id') &&
                  value.containsKey('value'))))
        return leaf(value, path);
      if (value is Map) {
        final entries = [
          for (final e in value.entries)
            [
              e.key,
              node(e.value, [...path, e.key as String]),
            ],
        ];
        if (entries.length <= 128) return ['m', entries];
        return [
          'q',
          [
            for (var i = 0; i < entries.length; i += 128)
              (leaf(entries.sublist(i, (i + 128).clamp(0, entries.length)), [
                ...path,
                '@map-page',
                '$i',
              ]) as List)[1],
          ],
        ];
      }
      if (value is List) {
        final children = [
          for (var i = 0; i < value.length; i++)
            node(value[i], [
              ...path,
              value[i] is Map
                  ? ((value[i] as Map)['id'] ?? (value[i] as Map)['name'] ?? i)
                        .toString()
                  : '$i',
            ], record: true),
        ];
        if (children.length <= 128) return ['l', children];
        return [
          'p',
          [
            for (var i = 0; i < children.length; i += 128)
              (leaf(children.sublist(i, (i + 128).clamp(0, children.length)), [
                ...path,
                '@page',
                '$i',
              ]) as List)[1],
          ],
        ];
      }
      // Checkpoints/recovery contain JSON snapshots as strings; split them too.
      if (value is String && (value.startsWith('{') || value.startsWith('['))) {
        try {
          final parsed = jsonDecode(value);
          if (jsonEncode(parsed) == value)
            return [
              'j',
              node(parsed, [...path, '@json']),
            ];
        } catch (_) {
          /* Ordinary text remains an ordinary string. */
        }
      }
      return leaf(value, path);
    }

    return JsonRecords(node(value, []), records);
  }

  static String join(Object? tree, String? Function(String) read) {
    Object? value(dynamic node) {
      if (node is! List || node.length != 2)
        throw const FormatException('Invalid local manifest');
      switch (node[0]) {
        case 'r':
          final raw = read(node[1] as String);
          if (raw == null) throw const FormatException('Missing local record');
          return jsonDecode(raw);
        case 'm':
          return <String, dynamic>{
            for (final entry in node[1] as List)
              entry[0] as String: value(entry[1]),
          };
        case 'l':
          return [for (final child in node[1] as List) value(child)];
        case 'j':
          return jsonEncode(value(node[1]));
        case 'q':
          return <String, dynamic>{
            for (final ref in node[1] as List)
              for (final entry in jsonDecode(
                read(ref as String) ??
                    (throw const FormatException('Missing local index')),
              ) as List)
                entry[0] as String: value(entry[1]),
          };
        case 'p':
          return [
            for (final ref in node[1] as List)
              for (final child in jsonDecode(
                read(ref as String) ??
                    (throw const FormatException('Missing local index')),
              ) as List)
                value(child),
          ];
        default:
          throw const FormatException('Unknown local node');
      }
    }

    return jsonEncode(value(tree));
  }

  static Set<String> refs(dynamic node, {String? Function(String)? read}) {
    if (node[0] == 'r') return {node[1] as String};
    if (node[0] == 'j') return refs(node[1], read: read);
    if (node[0] == 'm')
      return {for (final e in node[1] as List) ...refs(e[1], read: read)};
    if (node[0] == 'l')
      return {for (final e in node[1] as List) ...refs(e, read: read)};
    if (node[0] == 'p' || node[0] == 'q') {
      return {
        for (final ref in node[1] as List) ...{
          ref as String,
          for (final child in jsonDecode(
            read?.call(ref) ??
                (throw const FormatException('Missing local index')),
          ) as List)
            ...refs(node[0] == 'q' ? child[1] : child, read: read),
        },
      };
    }
    throw const FormatException('Unknown local node');
  }
}

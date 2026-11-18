import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/storage/json_records.dart';

void main() {
  test('lossless empty containers, ordered lists and JSON inside checkpoint strings', () {
    final source = {
      'elements': [
        {'id': 'a', 'text': '메모', 'photos': []},
      ],
      'empty': {},
      'null': null,
      'snapshot': jsonEncode({
        'version': 1,
        'elements': [
          {'id': 'a', 'text': '메모'},
        ],
      }),
    };
    final raw = jsonEncode(source),
        parts = JsonRecords.split(jsonEncode(source));
    expect(JsonRecords.join(parts.tree, (key) => parts.records[key]), raw);
  });
  test('one memo edit replaces only one record', () {
    String data(String text) => jsonEncode({
      'elements': [
        {'id': 'a', 'text': text},
        {'id': 'b', 'text': 'untouched'},
      ],
    });
    final a = JsonRecords.split(data('first')),
        b = JsonRecords.split(data('edited'));
    expect(b.records.keys.toSet().difference(a.records.keys.toSet()).length, 1);
    expect(a.records.keys.toSet().difference(b.records.keys.toSet()).length, 1);
  });
  test(
    'reordering stable IDs reuses records and missing chunks fail closed',
    () {
      final rows = [
        {'id': 'a', 'text': 'one'},
        {'id': 'b', 'text': 'two'},
      ];
      final a = JsonRecords.split(jsonEncode({'elements': rows}));
      final b = JsonRecords.split(
        jsonEncode({'elements': rows.reversed.toList()}),
      );
      expect(a.records.keys.toSet(), b.records.keys.toSet());
      expect(
        () => JsonRecords.join(a.tree, (_) => null),
        throwsFormatException,
      );
    },
  );
  test('5000 memo update changes one content record plus index', () {
    final rows = List.generate(
      5000,
      (i) => {'id': 'memo-$i', 'text': '생각 $i ${'본문 ' * 40}'},
    );
    final before = JsonRecords.splitValue({'elements': rows});
    rows[2500]['text'] = 'edited';
    final after = JsonRecords.splitValue({'elements': rows});
    final changed = after.records.keys.toSet().difference(
      before.records.keys.toSet(),
    );
    expect(
      JsonRecords.join(after.tree, (ref) => after.records[ref]),
      jsonEncode({'elements': rows}),
    );
    expect(
      JsonRecords.refs(after.tree, read: (ref) => after.records[ref]),
      after.records.keys.toSet(),
    );
    expect(changed.length, 2); // One memo and its 128-entry index page.
    final contentBytes = changed.fold<int>(
      0,
      (sum, key) => sum + utf8.encode(after.records[key]!).length,
    );
    final indexBytes = utf8.encode(jsonEncode(after.tree)).length;
    // ignore: avoid_print
    print(
      '5000 memos: changed memo + index page=$contentBytes bytes; commit index=$indexBytes bytes',
    );
  });

  test(
    'large coordinate maps and sync item maps use paged indexes losslessly',
    () {
      final source = {
        'positions': {
          for (var i = 0; i < 300; i++) 'memo-$i': [i * 1.0, i * 2.0],
        },
        'items': {
          for (var i = 0; i < 300; i++)
            'item-$i': {
              'kind': 'list:elements',
              'id': 'memo-$i',
              'value': {'text': 'memo $i'},
            },
        },
      };
      final parts = JsonRecords.splitValue(source);
      expect(
        JsonRecords.join(parts.tree, (ref) => parts.records[ref]),
        jsonEncode(source),
      );
      expect(
        JsonRecords.refs(parts.tree, read: (ref) => parts.records[ref]),
        parts.records.keys.toSet(),
      );
    },
  );
}

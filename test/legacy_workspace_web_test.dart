import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  test('pre-project-ID workspace restores projects, thoughts and boxes', () {
    final raw = jsonEncode({
      'version': 1,
      'elements': [
        {'id': 'old-thought', 'text': '기존 생각', 'createdAt': '2025-01-01T12:00:00.000', 'tags': ['자료']},
      ],
      'colors': {'기존 생각': 120},
      'notes': [
        for (final name in ['첫 프로젝트', '둘째 프로젝트'])
          {'content': '기존 본문', 'createdAt': '2025-01-01T12:00:00.000',
            'project': {'name': name, 'words': ['기존 생각'], 'document': '기존 본문',
              'paragraphs': [{'text': '옛 문단', 'role': 'body'}]}},
      ],
      'memoBoxes': [{'name': '이전 상자', 'color': 0xFF123456, 'ids': ['old-thought'], 'folder': '이전 폴더'}],
      'memoBoxFolders': ['이전 폴더'],
    });
    final restored = WorkspaceSnapshot.decode(raw);
    restored.apply();
    expect(restored.notes.length, 2);
    expect(restored.notes.map((n) => n.project!.id).toSet().length, 2);
    expect(restored.notes.every((n) => n.project!.content == '기존 본문'), isTrue);
    expect(elements.records['기존 생각']!.id, 'old-thought');
    expect(elements.records['기존 생각']!.tags, {'자료'});
    expect(memoBoxes.single.elementIds, {'old-thought'});
    final ids = restored.notes.map((n) => n.project!.id).toList();
    final again = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode(restored.notes));
    expect(again.notes.map((n) => n.project!.id), ids);
    expect(again.notes.first.project!.paragraphs.single.text, '옛 문단');
    elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); memoBoxFolderParents.clear();
  });

  test('legacy 32-bit random bound reproduces the web-only failure', () {
    // Dart web bitwise operations are 32-bit. Native-only tests missed this
    // invalid bound when an older project's missing ID was generated on load.
    expect(() => Random.secure().nextInt(1 << 32), throwsArgumentError);
  }, skip: !kIsWeb);
}

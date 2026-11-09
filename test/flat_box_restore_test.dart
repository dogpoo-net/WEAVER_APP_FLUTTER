import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  test('formerly nested boxes restore as separate boxes without losing thoughts', () {
    elements.clear(); memoBoxes.clear();
    final first = elements.add('상위 생각'), second = elements.add('하위 생각');
    memoBoxes.addAll([MemoBox('상위', ids: [first.id]), MemoBox('하위', ids: [second.id])]);
    final data = jsonDecode(WorkspaceSnapshot.encode([])) as Map<String, dynamic>;
    (data['memoBoxes'] as List).last['parentName'] = '상위';
    WorkspaceSnapshot.decode(jsonEncode(data)).apply();
    expect(memoBoxes.singleWhere((b) => b.name == '상위').elementIds, {first.id});
    expect(memoBoxes.singleWhere((b) => b.name == '하위').elementIds, {second.id});
    expect(elements.records.length, 2);
    expect(WorkspaceSnapshot.encode([]), isNot(contains('parentName')));
    elements.clear(); memoBoxes.clear();
  });
}

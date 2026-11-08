import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(elements.clear);
  test(
    'editing preserves identity/color and rejects collisions or empty content',
    () {
      final original = elements.add('생각 #기존');
      final color = exportWordColors()['생각'];
      elements.add('다른 생각');
      expect(elements.update('생각', '#태그'), isNotNull);
      expect(elements.update('생각', '다른 생각'), isNotNull);
      expect(elements.records['생각'], same(original));
      expect(elements.update('생각', '새로운 생각 #수정'), isNull);
      expect(elements.records['새로운 생각'], same(original));
      expect(original.tags, {'수정'});
      expect(exportWordColors()['새로운 생각'], color);
      expect(elements.words, isNot(contains('생각')));
    },
  );
  testWidgets(
    'metadata save persists renamed quick note, cancel leaves original',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = WorkspaceStorage(await SharedPreferences.getInstance());
      await tester.pumpWidget(MyApp(storage: storage));
      await tester.enterText(find.byKey(const ValueKey('quick-memo')), '생각');
      await tester.pump();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('생각'));
      await tester.tap(find.text('생각'));
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('element-editor'));
      await tester.enterText(editor, '취소한 수정');
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(elements.words, ['생각']);
      await tester.tap(find.text('생각'));
      await tester.pumpAndSettle();
      await tester.enterText(editor, '새로운 생각 #기록');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('저장'),
        ),
      );
      await tester.pumpAndSettle();
      final saved = WorkspaceSnapshot.decode(storage.read()!);
      expect(saved.notes.single.content, '새로운 생각');
      expect(saved.records.single.text, '새로운 생각');
      expect(saved.records.single.tags, {'기록'});
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_binding.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  test('linked ranges reject internal edits but allow surrounding edits and atomic removal', () {
    final c = BoundTextController('앞 원소 뒤', [const ElementBinding('id', 2, 4)]);
    c.value = const TextEditingValue(text: '앞 원수 뒤');
    expect(c.text, '앞 원소 뒤');
    c.value = const TextEditingValue(text: '앞 원가소 뒤');
    expect(c.text, '앞 원소 뒤');
    c.value = const TextEditingValue(text: '새 앞 원소 뒤');
    expect(c.bindings.single.start, 4);
    c.value = const TextEditingValue(text: '새 앞  뒤');
    expect(c.bindings, isEmpty);
    expect(c.text, '새 앞  뒤');
  });
  test('backspace and forward delete remove a complete link and preserve neighbours', () {
    for (final edited in ['앞 원 뒤', '앞 소 뒤']) {
      final c = BoundTextController('앞 원소 뒤', [const ElementBinding('id', 2, 4)]);
      c.value = TextEditingValue(text: edited, selection: const TextSelection.collapsed(offset: 3));
      expect(c.text, '앞  뒤');
      expect(c.bindings, isEmpty);
      expect(c.selection.extentOffset, 2);
      c.dispose();
    }
    final c = BoundTextController('앞 원소 뒤 연결 끝', [const ElementBinding('one', 2, 4), const ElementBinding('two', 7, 9)]);
    c.value = const TextEditingValue(text: '앞 원 뒤 연결 끝');
    expect(c.text, '앞  뒤 연결 끝');
    expect(c.bindings.single.id, 'two');
    expect(c.bindings.single.start, 5);
    expect(c.bindings.single.end, 7);
  });
  test('multiple links follow source updates without changing ordinary matching text', () {
    final c = BoundTextController('원소 / 원소 / 원소', [const ElementBinding('id', 0, 2), const ElementBinding('id', 5, 7)]);
    c.sync({'id': '긴 원소'});
    expect(c.text, '긴 원소 / 긴 원소 / 원소');
    expect(c.bindings.map((b) => b.start), [0, 7]);
    expect(c.bindings.map((b) => b.end), [4, 11]);
  });
  test('paragraph bindings survive backup and legacy paragraphs remain plain text', () {
    elements.clear();
    final record = elements.add('원소');
    final note = Note('원소')..paragraphs = [Paragraph('원소', ParagraphRole.body,
      bindings: [ElementBinding(record.id, 0, 2)])];
    final restored = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([note]));
    expect(restored.notes.single.paragraphs!.single.bindings.single.id, record.id);
  });
  for (final project in [false, true]) {
    testWidgets('assist binds a protected element in editor ($project)', (tester) async {
      elements.clear(); elements.add('관찰');
      await tester.pumpWidget(MaterialApp(home: ParagraphEditor(words: const ['관찰'], projectEditing: project)));
      final field = find.byKey(const ValueKey('paragraph-0'));
      await tester.enterText(field, '관'); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('suggestion-관찰'))); await tester.pumpAndSettle();
      final c = tester.widget<TextField>(field).controller! as BoundTextController;
      expect(c.bindings.single.id, elements.records['관찰']!.id);
      await tester.enterText(field, '관수'); await tester.pumpAndSettle();
      expect(c.text, '관찰');
      elements.update('관찰', '깊은 관찰'); await tester.pumpAndSettle();
      expect(c.text, '깊은 관찰');
      expect(tester.takeException(), isNull);
    });
  }
}

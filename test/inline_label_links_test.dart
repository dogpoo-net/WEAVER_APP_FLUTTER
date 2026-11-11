import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/document_markup.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/element_binding.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/caret_assist.dart';

void main() {
  setUp(elements.clear);
  test('exact aliases and safe URLs become atomic inline links', () {
    final target = elements.add('본문')..indexLabel = '자료';
    final c = LabelTextController();
    c.value = const TextEditingValue(text: '앞 [[표시명|자료]] 뒤', selection: TextSelection.collapsed(offset: 14));
    expect(c.text, '앞 표시명 뒤'); expect(c.bindings.single.id, 'label:${target.id}');
    c.value = const TextEditingValue(text: '앞 표시 뒤', selection: TextSelection.collapsed(offset: 4));
    expect(c.text, '앞  뒤'); expect(c.bindings, isEmpty);
    c.text = '[[웹|https://example.com/path?q=1#part]]';
    expect(c.text, '웹'); expect(c.bindings.single.id, startsWith('url:https://'));
    c.clear(); c.text = '[[위험|javascript:alert(1)]]'; expect(c.bindings, isEmpty);
    c.clear(); c.text = '[[미확정|없는 라벨]]'; expect(c.bindings, isEmpty);
    c.dispose();
  });
  test('a whole atomic link can be replaced but an interior edit is rejected', () {
    final c = LabelTextController('별칭', [const ElementBinding('url:https://example.com', 0, 2)]);
    c.value = const TextEditingValue(text: '별다'); expect(c.text, '별칭');
    c.value = const TextEditingValue(text: '새 본문'); expect(c.text, '새 본문'); expect(c.bindings, isEmpty);
    c.dispose();
  });
  test('duplicate label names require a chosen identity, and tags keep link offsets', () {
    final a = elements.add('A')..indexLabel = '같은 라벨';
    elements.add('B').indexLabel = '같은 라벨';
    expect(resolveLabelTarget('같은 라벨'), isNull);
    final c = LabelTextController();
    c.value = const TextEditingValue(text: '#태그 [[별칭|', selection: TextSelection.collapsed(offset: 9));
    c.insertLabel(a);
    final clean = cleanLinkedInput(c);
    expect(clean.text, '별칭'); expect(clean.tags, {'태그'});
    expect(clean.links.single.start, 0); expect(clean.links.single.end, 2);
    expect(clean.links.single.id, 'label:${a.id}'); c.dispose();
  });
  test('new links persist while obsolete connection data is discarded', () {
    final target = elements.add('원본')..indexLabel = '제목';
    final record = elements.addLinked('별칭', [ElementBinding('label:${target.id}', 0, 2)], {});
    final project = WritingProject([], [], name: '문서')..document = '별칭'..documentLinks = List.of(record.inlineLinks);
    final data = jsonDecode(WorkspaceSnapshot.encode([Note('문서')..project = project])) as Map<String, dynamic>;
    data['elements'][0]['connections'] = [record.id];
    WorkspaceSnapshot.decode(jsonEncode(data)).apply();
    expect(elements.records['별칭']!.inlineLinks.single.id, 'label:${target.id}');
    final restored = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([Note('문서')..project = project]));
    expect(restored.notes.single.project!.documentLinks.single.id, 'label:${target.id}');
    expect(jsonDecode(WorkspaceSnapshot.encode([]))['elements'][0].containsKey('connections'), isFalse);
  });
  testWidgets('empty alias target opens label assist and completes the alias', (tester) async {
    final target = elements.add('숨길 본문')..indexLabel = '검색 라벨';
    final c = LabelTextController(), focus = FocusNode();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CaretAssist(controller: c, focus: focus,
      useThoughtLabels: true, showWhenEmpty: false, words: [target.text], onWord: (_) => c.insertLabel(target),
      child: TextField(controller: c, focusNode: focus)))));
    await tester.enterText(find.byType(TextField), '[[표시명|'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('suggestion-${target.text}'))); await tester.pumpAndSettle();
    expect(c.text, '표시명'); expect(c.bindings.single.id, 'label:${target.id}');
    await tester.pumpWidget(const SizedBox()); c.dispose(); focus.dispose();
  });
  testWidgets('project markup renders headings, emphasis and alignment', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DocumentMarkup(text:
      '====== 제목 ======\n**굵게** //기울임// __밑줄__ --취소선--\n|왼쪽 |\n| 오른쪽|\n| 가운데 |'))));
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.first.textSpan!.toPlainText(), ' 제목 ');
    expect(texts[1].textSpan!.toPlainText(), '굵게 기울임 밑줄 취소선');
    expect(texts[2].textAlign, TextAlign.left); expect(texts[3].textAlign, TextAlign.right); expect(texts[4].textAlign, TextAlign.center);
    expect(documentTitle('====== 제목 ======'), '제목');
  });
  test('project heading titles resolve to stable identities and survive renaming and storage', () {
    final project = WritingProject([], [], name: '이전 제목')..document = '서문\n======문서 제목======\n내용';
    elements.indexProject(project);
    expect(documentTitle(project.content), '문서 제목');
    expect(labelAssistTargets(), contains('project:${project.id}'));
    final c = LabelTextController()..text = '[[문서|문서 제목]]';
    expect(c.text, '문서'); expect(c.bindings.single.id, 'project:${project.id}');
    project.document = '======새 제목======';
    expect(projectTarget(c.bindings.single.id), same(project));
    expect(assistTargetTitle('project:${project.id}'), '새 제목');
    final note = Note(c.text)..bindings = List.of(c.bindings);
    final snapshot = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([note, Note(project.content)..project = project]));
    expect(snapshot.notes.first.bindings.single.id, 'project:${project.id}');
    c.dispose();
  });
  test('code keeps literal link syntax and headings inside code are not project titles', () {
    elements.add('내용').indexLabel = '라벨';
    final c = LabelTextController()..text = '<code>[[표시|라벨]]</code> [[밖|라벨]]';
    expect(c.text, '<code>[[표시|라벨]]</code> 밖'); expect(c.bindings, hasLength(1));
    expect(documentTitle('<code>\n======코드======\n</code>\n=====실제 제목====='), '실제 제목');
    c.dispose();
  });
  testWidgets('compact heading syntax preserves spaces and multiline code stays literal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DocumentMarkup(text:
      '======제목======\n===== 여백 =====\n<code>**코드**\n==제목 아님==\n//코드//</code>'))));
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts[0].textSpan!.toPlainText(), '제목');
    expect(texts[1].textSpan!.toPlainText(), ' 여백 ');
    expect(texts[2].textSpan!.toPlainText(), '**코드**');
    expect(texts[3].textSpan!.toPlainText(), '==제목 아님==');
    expect(texts[4].textSpan!.toPlainText(), '//코드//');
  });

}

import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('project reference panel combines boxes and tags with OR', (tester) async {
    elements.clear(); memoBoxes.clear();
    final a = elements.add('상자 생각'), b = elements.add('태그 생각 #독서'); elements.add('나머지');
    memoBoxes.add(MemoBox('보관함', ids: [a.id]));
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentEditor(project: WritingProject([], [], name: '문서')..document = '내용')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-panel-toggle'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thought-filter-box-보관함'))); await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == a.text), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == b.text), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thought-filter-tag-독서'))); await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == b.text), findsOneWidget);
    expect(find.byKey(const ValueKey('project-tag-scroll')), findsNothing);
  });
}

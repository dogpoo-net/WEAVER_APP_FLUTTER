import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('project checkboxes select tags and show related thoughts without changing prose', (tester) async {
    tester.view.physicalSize = const Size(1200, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    elements.clear(); elements.add('읽은 생각 #독서'); elements.add('다른 생각 #여행');
    final project = WritingProject([], [], name: '프로젝트')..document = '내 본문';
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: project)));
    bool shown(String text) => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == text);
    expect(shown('읽은 생각'), isFalse);
    expect(find.widgetWithText(CheckboxListTile, '#독서'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-tag-독서'))); await tester.pumpAndSettle();
    expect(shown('읽은 생각'), isTrue); expect(shown('다른 생각'), isFalse);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, '내 본문');
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(project.tags, {'독서'}); expect(project.document, '내 본문');
    await tester.tap(find.byKey(const ValueKey('project-tag-독서'))); await tester.pumpAndSettle();
    expect(shown('읽은 생각'), isFalse);
    await tester.tap(find.text('저장')); await tester.pumpAndSettle(); expect(project.tags, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

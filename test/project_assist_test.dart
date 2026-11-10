import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('project title assist inserts an atomic alias and help replaces folder action', (tester) async {
    elements.clear();
    final source = WritingProject([], [], name: '작성')..document = '';
    final target = WritingProject([], [], name: '옛 이름')..document = '서문\n======참고 프로젝트======';
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: source, projects: [source, target])));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('project-document'));
    await tester.enterText(field, '[[별칭|참고'); await tester.pumpAndSettle();
    final suggestion = find.byKey(ValueKey('suggestion-project:${target.id}'));
    expect(tester.widget<WordBadge>(suggestion).project, isTrue);
    await tester.tap(suggestion); await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field).controller! as LabelTextController;
    expect(controller.text, '별칭'); expect(controller.bindings.single.id, 'project:${target.id}');
    controller.clear();
    await tester.enterText(field, '<code>참고'); await tester.pumpAndSettle();
    expect(suggestion, findsNothing);
    expect(find.byTooltip('프로젝트 폴더'), findsNothing);
    await tester.tap(find.byTooltip('작성 문법 안내')); await tester.pumpAndSettle();
    expect(find.text('프로젝트 작성 문법'), findsOneWidget);
    expect(find.textContaining('<code>code</code>'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

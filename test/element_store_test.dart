import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  setUp(elements.clear);
  test(
    'phrase identity, timestamp and longest non-overlapping occurrences',
    () {
      final a = elements.add('작은 생각');
      expect(identical(a, elements.add(' 작은 생각 ')), isTrue);
      expect(a.createdAt.isAfter(DateTime.now()), isFalse);
      elements.add('생각');
      expect(elements.matches('작은 생각, 작은 생각 그리고 생각').map((m) => m.word), [
        '작은 생각',
        '작은 생각',
        '생각',
      ]);
    },
  );
  testWidgets('project lists only used elements without global creation controls', (
    tester,
  ) async {
    elements.add('작은 생각');
    elements.add('다른 원소');
    elements.sources['standalone'] = [
      ElementSource('독립 문단', '작은 생각 작은 생각 다른 원소'),
    ];
    final project = WritingProject(
      [const Paragraph('작은 생각', ParagraphRole.body)],
      [],
      name: '시험',
    );
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: project)));
    expect(find.byKey(const ValueKey('project-document')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == '작은 생각'), findsOneWidget);
    expect(find.text('글로벌 원소 저장'), findsNothing);
    await tester.tap(find.byWidgetPredicate((w) => w is WordBadge && w.word == '작은 생각'));
    await tester.pumpAndSettle();
    expect(find.text('사용 1회 · 1개 위치'), findsOneWidget);
    expect(find.text('독립 문단 · 2회'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

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
    await tester.tap(find.text('원소'));
    await tester.pumpAndSettle();
    expect(find.text('작은 생각'), findsOneWidget);
    expect(find.text('다른 원소'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('글로벌 원소 저장'), findsNothing);
    expect(elements.words, ['작은 생각', '다른 원소']);
    await tester.tap(find.text('작은 생각'));
    await tester.pumpAndSettle();
    expect(find.text('사용 1회 · 1개 위치'), findsOneWidget);
    expect(find.text('시험 · 문단 1 · 1회'), findsOneWidget);
    expect(find.text('독립 문단 · 2회'), findsNothing);
    expect(find.text('함께 쓰인 원소가 없어요.'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(4));
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('미리보기'));
    await tester.pumpAndSettle();
    final linkText = tester.widget<Text>(
      find.descendant(
        of: find.byType(ElementLink),
        matching: find.byType(Text),
      ),
    );
    expect(linkText.style!.decorationStyle, TextDecorationStyle.dotted);
    expect(
      linkText.style!.decorationColor,
      wordBackgroundColor(tester.element(find.byType(ElementText)), '작은 생각'),
    );
    await tester.tap(find.byType(ElementLink));
    await tester.pumpAndSettle();
    expect(find.text('사용 1회 · 1개 위치'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';

void main() {
  setUp(elements.clear);
  testWidgets('usage links open and focus the exact distant occurrence', (
    tester,
  ) async {
    elements.add('기억');
    final project = WritingProject(
      [
        for (var i = 0; i < 25; i++) Paragraph('여백 문단 $i', ParagraphRole.body),
        const Paragraph('첫 기억. 두번째 기억을 담은 문장.', ParagraphRole.body),
      ],
      [],
      name: '프로젝트',
    );
    elements.indexProject(project);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showElementMetadata(context, '기억'),
              child: const Text('정보'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('정보'));
    await tester.pumpAndSettle();
    expect(find.text('사용 2회 · 1개 위치'), findsOneWidget);
    await tester.ensureVisible(find.text(' 두번째 기억을 담은 문장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(' 두번째 기억을 담은 문장'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectPage), findsOneWidget);
    final link = find.byKey(const ValueKey('element-10'));
    expect(link, findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<ElementLink>()
          ?.key,
      const ValueKey('element-10'),
    );
    expect(tester.getRect(link).top, greaterThanOrEqualTo(56));
    expect(tester.getRect(link).bottom, lessThanOrEqualTo(600));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('사용 2회 · 1개 위치'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/element_usage.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';
import 'package:weaver/main.dart';

void main() {
  setUp(elements.clear);
  List<Note> notes() => [
    Note('관찰'), // Creating a quick element is not a use in a saved sentence.
    Note('관찰 관찰 질문')..paragraphs = const [Paragraph('관찰 관찰 질문', ParagraphRole.body)],
    Note('프로젝트')..project = WritingProject(const [
      Paragraph('관찰 연결', ParagraphRole.body), Paragraph('질문 연결', ParagraphRole.body),
      Paragraph('관찰 질문 관찰', ParagraphRole.body),
    ], [], name: '프로젝트'),
  ];
  void records() {
    for (final word in ['관찰', '질문', '연결', '미사용']) { elements.add(word); }
    elements.records['미사용']!.hiddenFromSearch = true;
  }

  test('usage counts occurrences and co-occurrence counts distinct shared sentences', () {
    records();
    final usage = ElementUsage.fromNotes(notes(), elements);
    expect(usage.counts, {'관찰': 5, '질문': 3, '연결': 2, '미사용': 0});
    expect(usage.together['관찰'], {'질문': 2, '연결': 1});
    expect(usage.together['질문'], {'관찰': 2, '연결': 1});
    expect(usage.together['미사용'], isEmpty);
  });

  testWidgets('desktop single click shows related elements and double click opens metadata', (tester) async {
    records();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: AllThoughtsPage(notes: notes())));
    final grid = find.byKey(const ValueKey('all-thoughts-grid'));
    final badge = find.descendant(of: grid, matching: find.byWidgetPredicate((w) => w is WordBadge && w.word == '관찰'));
    final hiddenId = elements.records['미사용']!.id;
    expect(find.byKey(ValueKey('thought-$hiddenId')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(ValueKey('usage-${elements.records['관찰']!.id}'))).data, '5회');
    await tester.tap(badge);
    await tester.pump();
    // Relations change before the double-click timeout has elapsed.
    expect(find.byKey(ValueKey('together-${elements.records['질문']!.id}')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final relations = find.byKey(const ValueKey('thought-relations'));
    expect(tester.getRect(relations).left, greaterThanOrEqualTo(tester.getRect(grid).right));
    expect(tester.widget<Text>(find.byKey(ValueKey('together-${elements.records['질문']!.id}'))).data, '2문장');
    await tester.tap(badge);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('element-editor'))).controller!.text, '관찰');
    expect(tester.takeException(), isNull);
  });

  testWidgets('all thoughts filters case-insensitively, focuses the badge match, and preserves original metadata', (tester) async {
    const phrase = '앞부분의 긴 글귀가 이어집니다 다른 설명도 한참 이어집니다 Dart 검색할 중간 내용 그리고 뒷부분의 긴 글귀가 계속 이어집니다';
    elements.add(phrase);
    elements.add('다른 원소');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.android),
      home: const AllThoughtsPage(notes: [])));
    final search = find.byKey(const ValueKey('all-thoughts-search'));
    final before = tester.getRect(search);
    await tester.enterText(search, 'DART');
    await tester.pumpAndSettle();
    expect(find.byType(WordBadge), findsOneWidget);
    final badge = find.byType(WordBadge);
    expect(tester.widget<WordBadge>(badge).word, phrase);
    expect(tester.widget<WordBadge>(badge).query, 'DART');
    final text = tester.widget<Text>(find.descendant(of: badge, matching: find.byType(Text)));
    expect(text.textSpan!.toPlainText(), contains('Dart'));
    expect(tester.getRect(search).top, closeTo(before.top, 1));
    await tester.enterText(search, '없는 검색어');
    await tester.pumpAndSettle();
    expect(find.byType(WordBadge), findsNothing);
    expect(find.text('일치하는 원소가 없어요.'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.byType(WordBadge), findsNWidgets(2));
    await tester.enterText(search, 'dart');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WordBadge));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('element-editor'))).controller!.text, phrase);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile opens metadata on one tap', (tester) async {
    records();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.android), home: AllThoughtsPage(notes: notes())));
    final badge = find.byWidgetPredicate((w) => w is WordBadge && w.word == '관찰');
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('element-editor')), findsOneWidget);
  });

  testWidgets('main and menu expose all thoughts, and paragraph heading exposes plus', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(tester.getCenter(find.text('모든 생각 보기')).dx, greaterThan(tester.getCenter(find.text('문단 쓰기')).dx));
    await tester.tap(find.text('모든 생각 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(AllThoughtsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    final menu = find.byType(WorkspaceMenu);
    expect(find.descendant(of: menu, matching: find.text('모든 생각 보기')), findsOneWidget);
    expect(find.byTooltip('문단 추가'), findsOneWidget);
    await tester.tap(find.byTooltip('문단 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(ParagraphEditor), findsOneWidget);
  });
}

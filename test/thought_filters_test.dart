import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); });
  testWidgets('default thought view filters unclassified without navigation', (tester) async {
    final free = elements.add('미분류 생각');
    final filed = elements.add('상자 속 생각');
    memoBoxes.add(MemoBox('자료', ids: [filed.id]));
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    expect(find.byType(ThoughtBoxView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thought-filter-box-미분류')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${free.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thought-${filed.id}')), findsNothing);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('boxes and tags filter in place and all resets ($platform)', (tester) async {
      final first = elements.add('첫 메모 #독서');
      final second = elements.add('다른 메모 #여행');
      memoBoxes.add(MemoBox('테스트', ids: [first.id]));
      memoBoxes.add(MemoBox('빈 상자'));
      await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: platform), home: const AllThoughtsPage(initialView: ThoughtView.boxes, notes: [])));
      final all = find.byKey(const ValueKey('thought-filter-all'));
      expect(tester.widget<ChoiceChip>(all).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('thought-filter-box-테스트')));
      await tester.pumpAndSettle();
      expect(find.byType(ThoughtBoxView), findsOneWidget);
      expect(find.text('첫 메모'), findsOneWidget);
      expect(find.text('다른 메모'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('thought-filter-tag-여행')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('thought-${first.id}')), findsNothing);
      expect(find.byKey(ValueKey('thought-${second.id}')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('all-thoughts-search')), '없는 내용');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('thought-${second.id}')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('all-thoughts-search')), '');
      await tester.tap(all); await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('thought-${first.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('thought-${second.id}')), findsOneWidget);
      final empty = find.byKey(const ValueKey('thought-filter-box-빈 상자'));
      await tester.ensureVisible(empty); await tester.tap(empty); await tester.pumpAndSettle();
      expect(find.byType(ThoughtBoxView), findsOneWidget);
      expect(find.text('이 상자에 담긴 메모가 없어요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  for (final view in [ThoughtView.diagram, ThoughtView.page]) {
    testWidgets('canvas filters boxes and tags without navigation ($view)', (tester) async {
      final first = elements.add('첫 메모 #독서');
      elements.add('다른 메모 #여행');
      memoBoxes.add(MemoBox('테스트', ids: [first.id]));
      await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(initialView: view, notes: const [])));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('thought-filter-box-테스트')));
      await tester.pumpAndSettle();
      expect(find.text('첫 메모'), findsOneWidget);
      expect(find.text('다른 메모'), findsNothing);
      expect(find.byType(AllThoughtsPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('thought-filter-tag-여행')));
      await tester.pumpAndSettle();
      expect(find.text('첫 메모'), findsNothing);
      expect(find.text('다른 메모'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('thought-filter-all')));
      await tester.pumpAndSettle();
      expect(find.text('첫 메모'), findsOneWidget);
      expect(find.text('다른 메모'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

}

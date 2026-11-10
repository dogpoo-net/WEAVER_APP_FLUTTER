import 'package:flutter/material.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';

void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); memoBoxFolders.clear(); });
  testWidgets('attachment filters use OR and search stays fixed while scrolling', (tester) async {
    final photo = elements.add('사진만')..photos.add(const PhotoAttachment('p', 'photo'));
    final voice = elements.add('음성만')..recordings.add(const VoiceAttachment('v', 1000));
    final both = elements.add('둘 다')
      ..photos.add(const PhotoAttachment('p2', 'photo'))
      ..recordings.add(const VoiceAttachment('v2', 1000));
    for (var i = 0; i < 100; i++) { elements.add('스크롤할 긴 생각 $i'); }
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('all-thoughts-search'));
    final top = tester.getTopLeft(search);
    await tester.drag(find.byKey(const ValueKey('all-thoughts-grid')), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(search), top);
    await tester.tap(find.byTooltip('사진 있는 생각')); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${photo.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thought-${voice.id}')), findsNothing);
    await tester.tap(find.byTooltip('음성 있는 생각')); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${photo.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thought-${voice.id}')), findsOneWidget);
    expect(find.text('스크롤할 긴 생각 0'), findsNothing);
    expect(find.byKey(ValueKey('thought-${both.id}')), findsOneWidget);
    await tester.tap(find.byTooltip('사진 있는 생각')); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${voice.id}')), findsOneWidget);
  });
  testWidgets('unclassified title is left aligned and help replaces tag creation', (tester) async {
    final box = MemoBox('미분류'); memoBoxes.add(box);
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], initialBox: box)));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isFalse);
    expect(find.byTooltip('해시태그 만들기'), findsNothing);
    await tester.tap(find.byTooltip('사용 안내')); await tester.pumpAndSettle();
    expect(find.text('생각 보기 안내'), findsOneWidget);
    await tester.tap(find.text('닫기')); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('thought search matches hashtag with or without hash prefix', (tester) async {
    final tagged = elements.add('산책 기록 #여행');
    final other = elements.add('집에서 읽기 #독서');
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    await tester.pumpAndSettle();
    for (final query in ['여행', '#여행']) {
      await tester.enterText(find.byKey(const ValueKey('all-thoughts-search')), query); await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('thought-${tagged.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('thought-${other.id}')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opening a box selects it but allows switching to every other box', (tester) async {
    final first = elements.add('첫 상자 생각'), second = elements.add('다른 상자 생각');
    final one = MemoBox('하나', ids: [first.id]), two = MemoBox('둘', ids: [second.id]);
    memoBoxes.addAll([one, two]);
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], initialBox: one)));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-box-하나'))).selected, isTrue);
    expect(find.byKey(ValueKey('thought-${second.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('thought-filter-box-둘'))); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${second.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thought-${first.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thought-filter-box-하나'))); await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('thought-${first.id}')), findsNothing);
    expect(find.byKey(ValueKey('thought-${second.id}')), findsOneWidget);
  });
  for (final view in [ThoughtView.diagram, ThoughtView.page, ThoughtView.geolog]) {
    testWidgets('box entry keeps all footer choices in $view', (tester) async {
      final first = elements.add('첫 생각 #독서'), second = elements.add('다른 생각 #여행');
      final one = MemoBox('하나', ids: [first.id]), two = MemoBox('둘', ids: [second.id]);
      memoBoxes.addAll([one, two]);
      await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], initialBox: one, initialView: view)));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-box-하나'))).selected, isTrue);
      expect(find.byKey(const ValueKey('thought-filter-tag-여행')), findsOneWidget);
      expect(find.byTooltip('메모상자 폴더'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('thought-filter-box-둘'))); await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('thought-filter-box-둘'))).selected, isTrue);
      if (view != ThoughtView.geolog) {
        expect(find.text('다른 생각'), findsOneWidget);
        expect(find.text('첫 생각'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
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
      expect(find.byKey(ValueKey('thought-${first.id}')), findsOneWidget);
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
      expect(find.text('첫 메모'), findsOneWidget);
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  testWidgets('phrase elements remain visible and available to assist', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField).first, '작은 생각');
    await tester.pump();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('작은 생각'), findsOneWidget);
    await tester.ensureVisible(find.text('문단 쓰기'));
    await tester.tap(find.text('문단 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '생각');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-작은 생각')), findsOneWidget);
  });
  test('empty and composing first Hangul syllable match candidates', () {
    expect(matchesWord('관찰', ''), isTrue);
    expect(matchesWord('관찰', 'ㄱ'), isTrue);
    expect(matchesWord('관찰', '과'), isTrue);
    expect(matchesWord('관찰', '관'), isTrue);
    expect(matchesWord('관찰', '질'), isFalse);
  });
  testWidgets('first syllable suggests and replaces only the current word', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('문단 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '오늘의 관');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('suggestion-관찰')));
    await tester.tap(find.byKey(const ValueKey('suggestion-관찰')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paragraph-0')))
          .controller!
          .text,
      '오늘의 관찰',
    );
  });
  testWidgets('single paragraph opens preview with tags and can be edited or deleted', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('문단 쓰기'));
    await tester.pumpAndSettle();
    expect(find.byType(ToggleButtons), findsNothing);
    expect(find.text('다음 문단'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '독립된 문단 #문단태그 ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('독립된 문단'));
    await tester.tap(find.text('독립된 문단'));
    await tester.pumpAndSettle();
    expect(find.text('사용한 원소'), findsOneWidget);
    expect(find.text('#문단태그'), findsOneWidget);
    expect(find.textContaining('작성일 ·'), findsOneWidget);
    await tester.tap(find.byTooltip('문단 수정'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('paragraph-0'))).controller!.text, '독립된 문단');
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '수정된 문단');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('수정된 문단'), findsOneWidget);
    await tester.tap(find.byTooltip('문단 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('수정된 문단'), findsNothing);
  });
  testWidgets('theme switch retains draft and applies both palettes', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField).first, '작성 중인 생각');
    for (final entry in {
      '다크': Brightness.dark,
      '라이트': Brightness.light,
    }.entries) {
      await tester.tap(find.byTooltip('테마 선택'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text(entry.key),
          matching: find.byType(CheckedPopupMenuItem<Object>),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        entry.value,
      );
      expect(find.text('작성 중인 생각'), findsOneWidget);
    }
  });
  testWidgets('capture, search and edit preserve Markdown', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, '# 생각\n연결하기');
    await tester.pump();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(find.text('# 생각 연결하기'), findsOneWidget);
    await tester.ensureVisible(find.text('# 생각 연결하기'));
    await tester.tap(find.text('# 생각 연결하기'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('element-editor'));
    expect(tester.widget<TextField>(editor).controller!.text, '# 생각\n연결하기');
    expect(find.text('메모 다듬기'), findsNothing);
    await tester.enterText(editor, '수정한 생각');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('저장')),
    );
    await tester.pumpAndSettle();
    expect(find.text('수정한 생각'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '없는 검색어');
    await tester.pump();
    expect(find.text('일치하는 메모가 없어요'), findsOneWidget);
  });
  testWidgets('narrow screen and keyboard fit', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

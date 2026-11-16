import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/grid_columns_preference.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    thoughtSquareViewCache = null;
    thoughtGridColumns = GridColumnsPreference('weaver.thoughtGridColumns.v1');
    photoGridColumns = GridColumnsPreference('weaver.photoGridColumns.v1');
    elements.clear();
  });
  testWidgets(
    'delta refresh never unmounts thought collection or resets search/scroll/columns',
    (tester) async {
      for (var i = 0; i < 100; i++) {
        elements.add('메모 $i');
      }
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AllThoughtsPage(notes: [], onRefresh: () => pending.future),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ThoughtBoxView), findsOneWidget);
      expect(find.text('서버 변경을 불러오는 중입니다.'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('all-thoughts-search')),
        '메모',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('확대'));
      await tester.pumpAndSettle();
      expect(find.text('5열'), findsOneWidget);
      final state = tester.state(find.byType(ThoughtBoxView));
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('thought-square-grid')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scroll, const Offset(0, -180));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scroll).position.pixels;
      elements.update('메모 10', '메모 수정');
      pending.complete();
      await tester.pumpAndSettle();
      expect(identical(state, tester.state(find.byType(ThoughtBoxView))), true);
      expect(tester.state<ScrollableState>(scroll).position.pixels, offset);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('all-thoughts-search')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '메모',
      );
      expect(find.text('5열'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'thought and photo columns persist independently across tabs and cold cache',
    (tester) async {
      elements.add('메모');
      await tester.pumpWidget(
        const MaterialApp(home: AllThoughtsPage(notes: [])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('확대'));
      await tester.pumpAndSettle();
      expect(find.text('5열'), findsOneWidget);
      await tester.tap(find.text('사진'));
      await tester.pumpAndSettle();
      expect(find.text('6열'), findsOneWidget);
      await tester.tap(find.byTooltip('확대'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('확대'));
      await tester.pumpAndSettle();
      expect(find.text('4열'), findsOneWidget);
      await tester.tap(find.text('생각'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('5열'), findsOneWidget);
      await tester.tap(find.text('사진'));
      await tester.pumpAndSettle();
      expect(find.text('4열'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'weaver.thoughtGridColumns.v1',
        ),
        5,
      );
      thoughtGridColumns = GridColumnsPreference(
        'weaver.thoughtGridColumns.v1',
      );
      photoGridColumns = GridColumnsPreference('weaver.photoGridColumns.v1');
      thoughtSquareViewCache = null;
      await tester.pumpWidget(
        const MaterialApp(home: AllThoughtsPage(notes: [])),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('5열'), findsOneWidget);
      await tester.tap(find.text('사진'));
      await tester.pumpAndSettle();
      expect(find.text('4열'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

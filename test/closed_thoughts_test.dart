import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/thought_settings.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';

void main() {
  setUp(() { elements.clear(); showClosedThoughts = true; });
  testWidgets('main searches include closed thoughts last and render them grey', (tester) async {
    elements.add('생각 열림');
    elements.add('생각 닫힘').hiddenFromSearch = true;
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    await tester.pumpWidget(MyApp(storage: WorkspaceStorage(await SharedPreferences.getInstance())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-search')), '생각'); await tester.pumpAndSettle();
    final badges = tester.widgetList<WordBadge>(find.byType(WordBadge)).map((b) => b.word).toList();
    expect(badges.indexOf('생각 닫힘'), greaterThan(badges.indexOf('생각 열림')));
    final context = tester.element(find.byType(WordBadge).first);
    final color = wordBackgroundColor(context, '생각 닫힘');
    expect(color.r, color.g); expect(color.g, color.b);
  });
  testWidgets('closed modal stays available when closed thoughts are excluded', (tester) async {
    elements.add('보관된 생각').hiddenFromSearch = true;
    showClosedThoughts = false;
    await tester.pumpWidget(const MaterialApp(home: AllThoughtsPage(notes: [])));
    await tester.pumpAndSettle();
    expect(find.text('보관된 생각'), findsNothing);
    await tester.tap(find.text('닫힌 생각 보기')); await tester.pumpAndSettle();
    expect(find.text('보관된 생각'), findsOneWidget);
  });
  testWidgets('settings persist visibility and logout has no handler', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => showThoughtSettings(context, preferences), child: const Text('설정')))));
    await tester.tap(find.text('설정')); await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '로그아웃')).onTap, isNull);
    await tester.tap(find.text('닫힌 생각 조회')); await tester.pumpAndSettle();
    expect(showClosedThoughts, isFalse);
    expect(preferences.getBool(closedThoughtsPreference), isFalse);
    expect(find.text('오픈소스 사용 정보'), findsOneWidget);
  });
}

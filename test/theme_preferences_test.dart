import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('mode and color set restore before the first frame after restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    Future<void> choose(String label) async {
      await tester.tap(find.byTooltip('테마 선택')); await tester.pumpAndSettle();
      await tester.tap(find.text(label)); await tester.pumpAndSettle();
    }
    await choose('베이지');
    await choose('시스템 설정');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MyApp(storage: storage));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.colorScheme.surface, const Color(0xFFF8F4EC));
    await choose('라이트');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MyApp(storage: storage));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.surface, const Color(0xFFF8F4EC));
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid saved theme falls back without affecting the workspace', (tester) async {
    SharedPreferences.setMockInitialValues({WorkspaceStorage.themeKey: '{invalid'});
    await tester.pumpWidget(MyApp(storage: WorkspaceStorage(await SharedPreferences.getInstance())));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}

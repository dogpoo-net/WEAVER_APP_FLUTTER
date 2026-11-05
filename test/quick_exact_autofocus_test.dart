import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets('only a full literal match auto-selects during Korean composition without saving', (tester) async {
    elements.clear(); final source = elements.add('생각');
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.tap(field); await tester.pumpAndSettle();
    bool selected() => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == source.text && b.selected);
    const partial = TextEditingValue(text: '본문 생가', selection: TextSelection.collapsed(offset: 5), composing: TextRange(start: 3, end: 5));
    tester.testTextInput.updateEditingValue(partial); await tester.pumpAndSettle();
    expect(selected(), isFalse);
    const full = TextEditingValue(text: '본문 생각', selection: TextSelection.collapsed(offset: 5), composing: TextRange(start: 3, end: 5));
    tester.testTextInput.updateEditingValue(full); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    expect(tester.widget<TextField>(field).controller!.value.composing, full.composing);
    expect(tester.widget<TextField>(field).controller!.text, full.text);
    expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(full); await tester.pumpAndSettle();
    expect(selected(), isFalse);
    await tester.enterText(field, '본문 생'); await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(full); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '본문 ');
    expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
}

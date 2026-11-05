import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/main.dart';

void main() {
  testWidgets('exact phrase selects automatically, escape stays dismissed, and enter binds', (tester) async {
    elements.clear(); elements.add('작은 생각');
    await tester.pumpWidget(MaterialApp(theme: ThemeData(platform: TargetPlatform.linux),
      home: const ParagraphEditor(words: ['작은 생각', '작은 생각들'])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '오늘 작은 생각'); await tester.pumpAndSettle();
    bool selected() => tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == '작은 생각' && b.selected);
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
    expect(selected(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft); await tester.pumpAndSettle();
    expect(selected(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '오늘 작은 생각');
    expect(tester.takeException(), isNull);
  });
  testWidgets('quick memo completes existing phrases without saving on assist enter', (tester) async {
    await tester.pumpWidget(const MyApp());
    elements.add('작은 생각');
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '오늘 작은'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-작은 생각'))); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '오늘 작은 생각');
    await tester.enterText(field, '작은 생각'); await tester.pumpAndSettle();
    expect(tester.widgetList<WordBadge>(find.byType(WordBadge)).any((b) => b.word == '작은 생각' && b.selected), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '작은 생각');
    expect(tester.takeException(), isNull);
  });
}

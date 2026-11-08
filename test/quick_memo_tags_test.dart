import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('draft connection X removes only the pending link', (tester) async {
    await tester.pumpWidget(const MyApp());
    final target = elements.add('참고생각');
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '작성한본문 참고생');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-참고생각')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('remove-draft-link-${target.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(elements.records['작성한본문']!.connections, isEmpty);
    expect(elements.records['참고생각'], same(target));
    expect(target.connections, isEmpty);
  });
  testWidgets('Enter commits a composing hashtag without leaving its syllable in body', (tester) async {
    await tester.pumpWidget(const MyApp());
    final field = find.byKey(const ValueKey('quick-memo'));
    const text = '아직 한글 완성 버그가 있음 #위버';
    await tester.enterText(field, text);
    tester.testTextInput.updateEditingValue(TextEditingValue(text: text,
      selection: TextSelection.collapsed(offset: text.length), composing: TextRange(start: text.length - 1, end: text.length)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: '버', selection: TextSelection.collapsed(offset: 1)));
    await tester.pumpAndSettle();
    expect(elements.records['아직 한글 완성 버그가 있음']!.tags, {'위버'});
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(elements.records.containsKey('아직 한글 완성 버그가 있음 버'), isFalse);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));
  testWidgets('existing tag completion rejects the native final syllable echo before saving', (tester) async {
    await tester.pumpWidget(const MyApp());
    elements.add('기존 생각 #위버');
    final field = find.byKey(const ValueKey('quick-memo'));
    const text = '아직 한글 완성 버그가 있음 #위버';
    await tester.enterText(field, text);
    tester.testTextInput.updateEditingValue(TextEditingValue(text: text,
      selection: TextSelection.collapsed(offset: text.length), composing: TextRange(start: text.length - 1, end: text.length)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, '$text ');
    expect(elements.records.containsKey('아직 한글 완성 버그가 있음'), isFalse);
    tester.testTextInput.updateEditingValue(TextEditingValue(text: '$text 버',
      selection: TextSelection.collapsed(offset: text.length + 2)));
    await tester.pump();
    expect(controller.text, '$text ');
    tester.testTextInput.updateEditingValue(TextEditingValue(text: '$text 버\n',
      selection: TextSelection.collapsed(offset: text.length + 3)));
    await tester.pump();
    expect(controller.text, '$text ');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(elements.records['아직 한글 완성 버그가 있음']!.tags, {'위버'});
    expect(elements.records.containsKey('아직 한글 완성 버그가 있음 버'), isFalse);
    // A subsequent deliberate key may enter the same syllable normally.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.enterText(field, '버');
    expect(controller.text, '버');
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));
  testWidgets('quick memo retains inline hashtags and parses them on save without Enter', (tester) async {
    await tester.pumpWidget(const MyApp());
    final memo = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(memo, '기록할 생각 #독서 ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(memo).controller!.text, '기록할 생각 #독서 ');
    expect(find.byTooltip(RegExp(r'태그 삭제$')), findsNothing);
    await tester.enterText(memo, '기록할 생각 #아이디어');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(elements.records['기록할 생각']!.tags, {'아이디어'});
    expect(tester.widget<TextField>(memo).controller!.text, isEmpty);
    expect(find.byTooltip(RegExp(r'태그 삭제$')), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('Enter commits a composing hashtag without leaving its syllable in body', (tester) async {
    await tester.pumpWidget(const MyApp());
    final field = find.byKey(const ValueKey('quick-memo'));
    const text = '아직 한글 완성 버그가 있음 #위버';
    await tester.enterText(field, text);
    tester.testTextInput.updateEditingValue(TextEditingValue(text: text,
      selection: TextSelection.collapsed(offset: text.length), composing: TextRange(start: text.length - 1, end: text.length)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(elements.records['아직 한글 완성 버그가 있음']!.tags, {'위버'});
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(elements.records.containsKey('아직 한글 완성 버그가 있음 버'), isFalse);
    expect(tester.takeException(), isNull);
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

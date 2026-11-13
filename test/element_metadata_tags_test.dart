import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/tag_colors.dart';

void main() {
  testWidgets('metadata Enter registers known and new tags without a newline', (tester) async {
    elements.clear();final record=elements.add('본문');elements.add('다른 메모 #기존');
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showElementMetadata(context,record.text),child:const Text('보기'))))));
    await tester.tap(find.text('보기'));await tester.pumpAndSettle();
    final editor=find.byKey(const ValueKey('element-editor'));
    await tester.enterText(editor,'본문 #기');await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-#기존')),findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).controller!.text,'본문 ');
    expect(find.descendant(of:find.byKey(const ValueKey('element-tags')),matching:find.text('#기존')),findsOneWidget);
    await tester.enterText(editor,'본문 #신규');await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(const TextEditingValue(text:'본문 #신규\n',selection:TextSelection.collapsed(offset:7)));
    await tester.pumpAndSettle();expect(tester.widget<TextField>(editor).controller!.text,'본문 ');
    expect(find.descendant(of:find.byKey(const ValueKey('element-tags')),matching:find.text('#신규')),findsOneWidget);
    final controller=tester.widget<TextField>(editor).controller!;
    controller.value=const TextEditingValue(text:'본문 #한글\n',selection:TextSelection.collapsed(offset:7),composing:TextRange(start:4,end:6));
    controller.clearComposing();await tester.pumpAndSettle();expect(controller.text,'본문 ');
    await tester.enterText(editor,'본문\n다음 문장');await tester.pumpAndSettle();expect(tester.widget<TextField>(editor).controller!.text,'본문\n다음 문장');
    await tester.tap(find.text('닫기'));await tester.pumpAndSettle();
  });

  testWidgets('metadata color circle opens palette and updates the thought', (tester) async {
    elements.clear(); final record = elements.add('색상 메모 #태그');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showElementMetadata(context, record.text), child: const Text('보기'))))));
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    expect(tester.getCenter(find.byKey(const ValueKey('thought-color'))).dx,
      greaterThan(tester.getCenter(find.byKey(const ValueKey('element-tags'))).dx));
    await tester.tap(find.byKey(const ValueKey('thought-color'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hashtag-color-16'))); await tester.pumpAndSettle();
    expect(record.labelColor, isNull);
    await tester.tap(find.text('생각 닫기')); await tester.pumpAndSettle();
    expect(record.hiddenFromSearch, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('thought-color'))).onPressed, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '저장')); await tester.pumpAndSettle();
    expect(record.labelColor, hashtagPalette[16].toARGB32());
    expect(record.hiddenFromSearch, isTrue);
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    await tester.tap(find.text('생각 닫기')); await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('thought-color'))).onPressed, isNotNull);
    await tester.tap(find.text('닫기')); await tester.pumpAndSettle();
    expect(record.hiddenFromSearch, isTrue);
    expect(record.labelColor, hashtagPalette[16].toARGB32());
    expect(record.text, '색상 메모');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('metadata treats tags as separate editable data and keeps prose clean', (tester) async {
    elements.clear();
    final record = elements.add('원래 본문 #기존');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showElementMetadata(context, record.text), child: const Text('보기'))))));
    await tester.tap(find.text('보기')); await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('element-editor'));
    expect(tester.widget<TextField>(editor).controller!.text, '원래 본문');
    expect(find.descendant(of: find.byKey(const ValueKey('element-tags')), matching: find.text('#기존')), findsOneWidget);
    await tester.enterText(editor, '새 본문 #추가 '); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).controller!.text, '새 본문 ');
    expect(find.text('#추가'), findsOneWidget);
    expect(record.tags, {'기존'});
    await tester.tap(find.byTooltip('#기존 태그 삭제')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장')); await tester.pumpAndSettle();
    expect(record.text, '새 본문');
    expect(record.tags, {'추가'});
    expect(record.text, isNot(contains('#')));
    expect(tester.takeException(), isNull);
  });
}

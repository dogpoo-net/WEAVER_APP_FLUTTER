import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('quick memo moves completed tags out of body and saves them', (tester) async {
    await tester.pumpWidget(const MyApp());
    final memo = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(memo, '기록할 생각 #독서 ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(memo).controller!.text, isNot(contains('#독서')));
    expect(find.widgetWithText(TextButton, '#독서'), findsOneWidget);
    await tester.enterText(memo, '기록할 생각 #아이디어 ');
    await tester.pumpAndSettle();
    expect(find.byTooltip(RegExp(r'태그 삭제$')), findsNWidgets(2));
    await tester.tap(find.byTooltip('#독서 태그 삭제'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(elements.records['기록할 생각']!.tags, {'아이디어'});
    expect(tester.widget<TextField>(memo).controller!.text, isEmpty);
    expect(find.byTooltip(RegExp(r'태그 삭제$')), findsNothing);
  });
}

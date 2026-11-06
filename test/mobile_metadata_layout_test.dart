import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_menu.dart';

void main() {
  testWidgets('mobile menu fills the space between equal side margins', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => const WorkspaceMenu(projects: [])), child: const Text('열기'))))));
    await tester.tap(find.text('열기')); await tester.pumpAndSettle();
    final box = find.descendant(of: find.byType(WorkspaceMenu), matching: find.byWidgetPredicate((w) =>
      w is SizedBox && w.width == double.infinity && w.height == double.infinity));
    final rect = tester.getRect(box);
    expect(rect.left, closeTo(390 - rect.right, .1));
    expect(rect.width, greaterThan(320));
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile metadata has an unclipped label, compact controls and no usage features', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    elements.clear();
    final thought = elements.add('내용 #태그'); final peer = elements.add('연결된 생각');
    elements.connect(thought.id, [peer.id]);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder())),
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showElementMetadata(context, thought.text), child: const Text('정보'))))));
    await tester.tap(find.text('정보')); await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(tester.getSize(dialog).width, greaterThan(330));
    final editor = find.byKey(const ValueKey('element-editor'));
    final label = find.text('원소 내용');
    final scroll = find.descendant(of: dialog, matching: find.byType(SingleChildScrollView));
    expect(tester.getTopLeft(label).dy, greaterThanOrEqualTo(tester.getTopLeft(scroll).dy));
    expect(tester.getTopLeft(label).dy, greaterThan(tester.getBottomRight(find.byKey(const ValueKey('element-tags'))).dy));
    expect(tester.getTopLeft(find.text('비활성')).dy, greaterThan(tester.getBottomRight(editor).dy));
    final date = find.byKey(const ValueKey('element-created-at'));
    expect(tester.getTopLeft(date).dy, greaterThan(tester.getBottomRight(find.text('비활성')).dy));
    expect(find.byKey(const ValueKey('element-connections-divider')), findsOneWidget);
    for (final removed in ['검색에서 숨기기', '메인과 원소 어시스트에 표시하지 않습니다.', '생성일', '프로젝트 사용', '사용 위치', '함께 쓰인 원소', '원소 삭제']) {
      expect(find.text(removed), findsNothing);
    }
    expect(tester.widget<AlertDialog>(dialog).actions!.length, 3);
    final divider = find.byKey(const ValueKey('element-actions-divider'));
    expect(divider, findsOneWidget);
    expect(tester.getTopLeft(date).dy, greaterThanOrEqualTo(tester.getBottomRight(divider).dy));
    expect(tester.getBottomRight(date).dx, closeTo(tester.getBottomRight(divider).dx, .1));
    final save = find.widgetWithText(FilledButton, '저장');
    expect(tester.getTopLeft(save).dy - tester.getBottomRight(date).dy, greaterThanOrEqualTo(10));
    expect(tester.widget<FilledButton>(save).style?.backgroundColor, isNull);
    expect(tester.getSize(find.widgetWithText(FilledButton, '저장')).height, lessThanOrEqualTo(40));
    expect(tester.getSize(find.widgetWithText(TextButton, '생각 삭제')).height, lessThanOrEqualTo(40));
    await tester.tap(find.text('비활성')); await tester.pumpAndSettle();
    expect(thought.hiddenFromSearch, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

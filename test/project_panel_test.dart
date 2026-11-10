import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  WritingProject project() {
    elements.clear();
    for (var i = 0; i < 80; i++) { elements.add('참고할 생각 $i #글 #분류$i'); }
    return WritingProject([], [], name: '작성 중')..document = List.generate(100, (i) => '본문 $i').join('\n')..tags.add('글');
  }
  testWidgets('desktop references are wider with independent thought, tag and document scrolling', (tester) async {
    tester.view.physicalSize = const Size(1200, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: project()))); await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('project-reference-panel'))).width, greaterThanOrEqualTo(400));
    final thoughts = find.byKey(const ValueKey('project-thought-scroll'));
    final tags = find.byKey(const ValueKey('project-tag-scroll'));
    expect(tester.getTopLeft(tags).dx, greaterThan(tester.getTopRight(thoughts).dx));
    final thoughtController = tester.widget<SingleChildScrollView>(thoughts).controller!;
    final tagController = tester.widget<ListView>(tags).controller!;
    final body = tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).scrollController!;
    await tester.drag(tags, const Offset(0, -180)); await tester.pumpAndSettle();
    expect(tagController.offset, greaterThan(0)); expect(thoughtController.offset, 0); expect(body.offset, 0);
    final tagOffset = tagController.offset;
    await tester.drag(thoughts, const Offset(0, -180)); await tester.pumpAndSettle();
    expect(thoughtController.offset, greaterThan(0)); expect(tagController.offset, tagOffset); expect(body.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('mobile panel toggles from a fixed button and preserves prose above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetViewInsets);
    final draft = project();
    await tester.pumpWidget(MaterialApp(home: ProjectPage(project: draft))); await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('project-panel-toggle'));
    final panel = find.byKey(const ValueKey('project-reference-panel'));
    expect(panel, findsNothing);
    await tester.tap(toggle); await tester.pumpAndSettle(); expect(panel, findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(toggle).dy, lessThanOrEqualTo(544));
    expect(tester.getSize(toggle).height, lessThanOrEqualTo(30));
    expect(find.byKey(const ValueKey('project-name')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('project-tag-search'))).height, lessThanOrEqualTo(38));
    expect(tester.getSize(find.byKey(const ValueKey('project-document'))).height, greaterThan(80));
    await tester.tap(toggle); await tester.pumpAndSettle(); expect(panel, findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, draft.document);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

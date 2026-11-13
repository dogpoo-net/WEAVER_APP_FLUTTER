import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/thought_settings.dart';

void main() {
  setUp(() => showClosedThoughts = true);
  WritingProject project() {
    elements.clear();
    for (var i = 0; i < 80; i++) { elements.add('참고할 생각 $i #글 #분류$i'); }
    return WritingProject([], [], name: '작성 중')..document = List.generate(100, (i) => '본문 $i').join('\n')..tags.add('글');
  }
  testWidgets('project references react to closed thought visibility changes', (tester) async {
    elements.clear();
    elements.add('열린 참고');
    elements.add('닫힌 참고').hiddenFromSearch = true;
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentEditor(project: WritingProject([], [], name: '필터 검증'))));
    await tester.pumpAndSettle();
    expect(find.text('닫힌 참고'), findsOneWidget);
    showClosedThoughts = false; elements.refreshVisibility();
    await tester.pumpAndSettle();
    expect(find.text('닫힌 참고'), findsNothing);
    expect(find.text('열린 참고'), findsOneWidget);
    showClosedThoughts = true; elements.refreshVisibility();
    await tester.pumpAndSettle();
    expect(find.text('닫힌 참고'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('desktop reference list scrolls independently above a full-width filter footer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentEditor(project: project()))); await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('project-reference-panel'))).width, greaterThanOrEqualTo(400));
    expect(tester.getCenter(find.byKey(const ValueKey('project-thought-panel-toggle'))).dx,greaterThan(tester.getRect(find.byKey(const ValueKey('project-reference-panel'))).right));
    expect(find.byKey(const ValueKey('project-box-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('project-panel-toggle'))); await tester.pumpAndSettle();
    final thoughts = find.byKey(const ValueKey('project-thought-scroll'));
    final thoughtController = tester.widget<SingleChildScrollView>(thoughts).controller!;
    final body = tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).scrollController!;
    await tester.drag(thoughts, const Offset(0, -180)); await tester.pumpAndSettle();
    expect(thoughtController.offset, greaterThan(0)); expect(body.offset, 0);
    expect(find.byKey(const ValueKey('project-tag-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('thought-filter-all')), findsOneWidget);
    final footer = tester.getRect(find.byKey(const ValueKey('project-box-panel')));
    final reference = tester.getRect(find.byKey(const ValueKey('project-reference-panel')));
    expect(footer.width, 1200); expect(footer.left, 0);
    expect(footer.top, greaterThanOrEqualTo(reference.bottom));
    expect(tester.getTopLeft(find.byKey(const ValueKey('project-document'))).dy, closeTo(tester.getRect(find.byKey(const ValueKey('document-editor-toolbar'))).bottom + 2, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('mobile keeps equal document and reference panes while keyboard folds only box filters', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetViewInsets);
    final draft = project();
    await tester.pumpWidget(MaterialApp(builder: (context, child) => Actions(actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(onInvoke: (intent) { intent.focusNode.unfocus(); return null; }),
    }, child: child!), home: ProjectDocumentEditor(project: draft))); await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('project-panel-toggle'));
    final panel = find.byKey(const ValueKey('project-reference-panel'));
    final boxes = find.byKey(const ValueKey('project-box-panel'));
    final document = find.byKey(const ValueKey('project-document'));
    expect(panel, findsOneWidget); expect(boxes, findsNothing);
    final thoughtToggle = find.byKey(const ValueKey('project-thought-panel-toggle'));
    expect(tester.getTopLeft(thoughtToggle).dy, lessThan(tester.getTopLeft(toggle).dy));
    final initialHeight = tester.getSize(document).height;
    await tester.tap(thoughtToggle); await tester.pumpAndSettle();
    expect(panel, findsNothing); expect(boxes, findsNothing);
    expect(tester.getSize(document).height, greaterThan(initialHeight));
    await tester.tap(toggle); await tester.pumpAndSettle();
    expect(boxes, findsOneWidget); expect(panel, findsNothing);
    await tester.tap(toggle); await tester.tap(thoughtToggle); await tester.pumpAndSettle();
    expect(panel, findsOneWidget);

    await tester.tap(toggle); await tester.pumpAndSettle(); expect(boxes, findsOneWidget);
    await tester.tap(document); await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(toggle).dy, lessThanOrEqualTo(544));
    expect(tester.getSize(toggle).height, lessThanOrEqualTo(30));
    expect(find.byKey(const ValueKey('project-name')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('project-reference-search'))).height, lessThanOrEqualTo(38));
    expect(tester.getSize(find.byKey(const ValueKey('project-document'))).height, greaterThan(80));
    expect(boxes, findsNothing); expect(panel, findsOneWidget);
    expect(tester.getSize(document).height, closeTo(tester.getSize(panel).height, 1));
    final focus = tester.widget<TextField>(document).focusNode!;
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(tester.getBottomLeft(panel) + const Offset(2, -2)); await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.tap(toggle); await tester.pumpAndSettle(); expect(boxes, findsOneWidget);
    await tester.tap(toggle); await tester.pumpAndSettle(); expect(boxes, findsNothing); expect(panel, findsOneWidget);
    await tester.tap(find.byTooltip('키보드 내리기')); await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text, draft.document);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

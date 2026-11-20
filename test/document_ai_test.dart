import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/document_ai_panel.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/project_document_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  Future<WorkspaceStorage> storage() async {
    SharedPreferences.setMockInitialValues({});
    return WorkspaceStorage(await SharedPreferences.getInstance());
  }

  setUp(() {
    elements.clear();
    elements.add('담을 생각');
    elements.add('다른 생각');
  });

  testWidgets(
    'mobile selects a thought, requests a summary and inserts below the caret',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      elements.records['담을 생각']!.indexLabel = '자료 라벨';
      elements.indexProject(
        WritingProject([], [], name: '참고 문서')..document = '======참고 문서======',
      );
      Map<String, Object?>? sent;
      final workspace = await storage()
        ..documentAiRequest = (input) async {
          sent = input;
          return {'text': '정리한 문장'};
        };
      final doc = WritingProject([], [], name: '문서')..document = '첫 줄\n다음 줄';
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectDocumentEditor(project: doc, storage: workspace),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(const ValueKey('project-document')))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.tap(find.byTooltip('AI 문장 생성'));
      await tester.pumpAndSettle();
      final panel = find.byType(DocumentAiPanel);
      final search = find.widgetWithText(TextField, '생각, 라벨 찾기');
      await tester.enterText(search, '참고 문서');
      await tester.pumpAndSettle();
      expect(find.text('담을 생각이 없습니다.'), findsOneWidget);
      await tester.enterText(search, '자료 라벨');
      await tester.pumpAndSettle();
      final label = find.descendant(
        of: panel,
        matching: find.textContaining('라벨:자료 라벨', findRichText: true),
      );
      await tester.tap(label);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('생성'));
      await tester.tap(find.text('생성'));
      await tester.pumpAndSettle();
      expect(sent!['material'], '담을 생각');
      expect(sent!['length'], 'medium');
      expect(find.text('정리한 문장'), findsOneWidget);
      final copy = find.byTooltip('복사');
      final insert = find.widgetWithText(FilledButton, '현재 위치에 삽입');
      expect(copy, findsOneWidget);
      expect(
        tester.getCenter(copy).dy,
        closeTo(tester.getCenter(insert).dy, 1),
      );

      await tester.tap(find.text('현재 위치에 삽입'));
      await tester.pumpAndSettle();
      expect(controller.text, '첫 줄\n정리한 문장\n다음 줄');
    },
  );

  testWidgets(
    'desktop AI panel accepts thought drags and has a resize handle',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, Object?>? sent;
      final workspace = await storage()
        ..documentAiRequest = (input) async {
          sent = input;
          return {'text': '만든 문장'};
        };
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectDocumentEditor(
            project: WritingProject([], [], name: '문서'),
            storage: workspace,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.byType(DocumentAiPanel);
      final divider = find.byKey(const ValueKey('document-ai-divider'));
      final height = tester.getSize(panel).height;
      final input = find.descendant(
        of: panel,
        matching: find.byType(quill.QuillEditor),
      );
      final prompt = find.widgetWithText(TextField, '프롬프트');
      final originalInputHeight = tester.getSize(input).height;
      final originalPromptTop = tester.getTopLeft(prompt).dy;
      await tester.drag(divider, const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, greaterThan(height));
      expect(tester.getSize(input).height, greaterThan(originalInputHeight));
      expect(tester.getTopLeft(prompt).dy, closeTo(originalPromptTop, 1));
      expect(
        find.byKey(const ValueKey('document-reference-divider')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('project-reference-search')),
        findsOneWidget,
      );

      final target = tester.widget<DragTarget<Object>>(
        find.descendant(of: panel, matching: find.byType(DragTarget<Object>)),
      );
      final rect = tester.getRect(input);
      final start = rect.topLeft + const Offset(9, 13);
      final end = rect.topRight + const Offset(-10, 13);
      for (final (name, position) in [('담을 생각', start), ('다른 생각', end)]) {
        final drop = DragTargetDetails(
          data: InlineLinkDrag(name),
          offset: position,
        );
        expect(target.onWillAcceptWithDetails!(drop), isTrue);
        target.onAcceptWithDetails!(drop);
        await tester.pumpAndSettle();
      }
      final resultTab = find.widgetWithText(InkWell, '결과');
      expect(tester.widget<InkWell>(resultTab).onTap, isNull);
      final composeTab = find.widgetWithText(InkWell, 'AI 문장 생성');
      expect(
        tester.getSize(resultTab).width,
        closeTo((tester.getSize(panel).width - 10) / 2, 1),
      );
      expect(tester.getRect(composeTab).right, tester.getRect(resultTab).left);
      expect(
        tester.getRect(input).left,
        closeTo(tester.getRect(composeTab).left, 1),
      );
      expect(
        tester.getRect(input).right,
        closeTo(tester.getRect(resultTab).right, 1),
      );

      final secondBadge = find.descendant(
        of: panel,
        matching: find.text('다른 생각'),
      );
      final badgeDrag = tester.widget<Draggable>(
        find
            .ancestor(
              of: secondBadge,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .first,
      );
      target.onAcceptWithDetails!(
        DragTargetDetails(data: badgeDrag.data!, offset: start),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(end);
      await tester.pump();
      final editor = tester.widget<quill.QuillEditor>(input);
      expect(editor.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      var caret = 1;
      for (final chunk in [' 사이에', ' 입력 ']) {
        final original = editor.controller.plainTextEditingValue.text;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: original.replaceRange(caret, caret, chunk),
            selection: TextSelection.collapsed(offset: caret + chunk.length),
          ),
        );
        caret += chunk.length;
        await tester.pump();
        expect(
          tester.widget<quill.QuillEditor>(input).focusNode,
          same(editor.focusNode),
        );
        expect(editor.focusNode.hasFocus, isTrue);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('생성'));
      await tester.pumpAndSettle();
      expect(sent!['material'], matches(r'^다른 생각\s+사이에 입력\s+담을 생각$'));
      expect(find.text('만든 문장'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'AI 문장 생성'));
      await tester.pumpAndSettle();
      final firstBadge = find.descendant(
        of: panel,
        matching: find.text('담을 생각'),
      );
      final removeDrag = tester.widget<Draggable>(
        find
            .ancestor(
              of: firstBadge,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .first,
      );
      removeDrag.onDraggableCanceled!(Velocity.zero, Offset.zero);
      await tester.pumpAndSettle();
      expect(firstBadge, findsNothing);
      expect(secondBadge, findsOneWidget);

      final length = find.byTooltip('문장 길이 선택');
      await tester.ensureVisible(length);
      await tester.pumpAndSettle();
      final anchor = tester.getRect(length);
      await tester.tap(length);
      await tester.pumpAndSettle();
      final shortOption = find.widgetWithText(MenuItemButton, '짤막');
      expect(
        tester.getRect(shortOption).left,
        greaterThanOrEqualTo(anchor.right),
      );
      expect(tester.getSize(shortOption).height, greaterThanOrEqualTo(34));
      await tester.tap(shortOption);
      await tester.pumpAndSettle();

      final viewport = find
          .ancestor(of: panel, matching: find.byType(ClipRect))
          .first;
      final originalHeight = tester.getSize(viewport).height;
      final handle = tester.getCenter(divider);
      final dragToEdge = await tester.startGesture(handle);
      await dragToEdge.moveTo(handle + Offset(0, originalHeight - 24));
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(tester.getSize(viewport).height, closeTo(24, 1));
      expect(tester.getSize(panel).height, 220);
      expect(
        tester.getSize(panel).height,
        greaterThan(tester.getSize(viewport).height),
      );
      await dragToEdge.up();
      await tester.pumpAndSettle();

      await tester.drag(divider, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(divider, findsOneWidget);
      await tester.drag(divider, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(secondBadge, findsOneWidget);
    },
  );
}

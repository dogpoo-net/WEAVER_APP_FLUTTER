import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/keyboard_viewport.dart';
import 'package:weaver/features/inbox/caret_assist.dart';

void main() {
  test('already resized browser viewport does not subtract keyboard twice', () {
    final media = MediaQueryData(size: const Size(390, 524),
      viewInsets: const EdgeInsets.only(bottom: 320));
    expect(effectiveKeyboardInset(media, visibleHeight: 524), 0);
    expect(effectiveKeyboardInset(media.copyWith(size: const Size(390, 844)),
      visibleHeight: 524), 320);
  });

  testWidgets('adding a paragraph focuses its field and scrolls within body bounds', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(words: ['기억'])));
    await tester.tap(find.text('다음 문단'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('paragraph-1')));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    final list = tester.widget<ListView>(find.byKey(const ValueKey('paragraph-scroll')));
    expect(list.controller!.offset, closeTo(list.controller!.position.maxScrollExtent, 1));
    final popup = tester.getRect(find.byKey(const ValueKey('assist-popup')));
    expect(popup.bottom, closeTo(524, 1));
    expect(tester.getRect(find.byKey(const ValueKey('paragraph-1'))).bottom,
      lessThanOrEqualTo(popup.top));
    expect(find.text('원소 어시스트'), findsNothing);
    expect(find.byTooltip('후보 닫기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final resizeViewport in [false, true]) {
    testWidgets(
      'keyboard ${resizeViewport ? "viewport resize" : "inset"} preserves the paragraph and reserves only panel height',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          MaterialApp(
            home: ParagraphEditor(
              words: const ['기억'],
              initial: List.generate(
                8,
                (i) => Paragraph(i == 0 ? '' : '문단 $i', ParagraphRole.body),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('paragraph-0')));
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('paragraph-scroll'));
        final controller = tester.widget<ListView>(list).controller!;
        final before = controller.offset;
        if (resizeViewport) {
          tester.view.physicalSize = const Size(390, 524);
        } else {
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        }
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(controller.offset, closeTo(before, 1));
        expect(controller.offset, lessThan(controller.position.maxScrollExtent));
        expect((tester.widget<ListView>(list).padding! as EdgeInsets).bottom,
          20 + mobileAssistHeight(MediaQueryData(size: const Size(390, 524))));
        expect(tester.getBottomRight(list).dy, closeTo(524, 1));
        final popup = tester.getRect(find.byKey(const ValueKey('assist-popup')));
        expect(popup.left, 0);
        expect(popup.width, 390);
        expect(popup.bottom, closeTo(524, 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mobile candidates scroll inside a fixed full-width bottom panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: ParagraphEditor(
          words: List.generate(40, (i) => '원소${i.toString().padLeft(2, '0')}'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paragraph-0')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final popup = find.byKey(const ValueKey('assist-popup'));
    final bounds = tester.getRect(popup);
    expect(bounds.left, 0);
    expect(bounds.width, 390);
    expect(bounds.bottom, closeTo(544, 1));
    expect(bounds.bottom, lessThanOrEqualTo(544));
    final scroll = find.descendant(
      of: popup,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('suggestion-원소39')),
      100,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(popup), bounds);
    await tester.tap(find.byKey(const ValueKey('suggestion-원소39')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paragraph-0')))
          .controller!
          .text,
      '원소39',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile assist slides in and out over 200ms', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: ParagraphEditor(words: ['기억'])),
    );
    final field = find.byKey(const ValueKey('paragraph-0'));
    final popup = find.byKey(const ValueKey('assist-popup'));
    await tester.tap(field);
    await tester.pump();
    await tester.pump();
    final start = tester.getRect(popup);
    await tester.pump(const Duration(milliseconds: 100));
    final halfway = tester.getRect(popup);
    expect(halfway.top, lessThan(start.top));
    await tester.pump(const Duration(milliseconds: 100));
    final shown = tester.getRect(popup);
    expect(shown.top, lessThan(halfway.top));
    expect(shown.bottom, closeTo(844, 1));
    tester.widget<TextField>(field).focusNode!.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(popup, findsOneWidget);
    expect(tester.getRect(popup).top, greaterThan(shown.top));
    await tester.pump(const Duration(milliseconds: 100));
    // Flush the frame that unmounts the overlay after animation completion.
    // Allow one display frame for floating-point ticker boundary rounding.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    // A new query can show the panel again after dismissal.
    await tester.enterText(field, '기');
    await tester.pumpAndSettle();
    expect(popup, findsOneWidget);
    expect(tester.getRect(popup).bottom, closeTo(844, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('project preview uses unsaved text and returns intact', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ParagraphEditor(
          projectEditing: true,
          words: [],
          initial: [Paragraph('기존 제목', ParagraphRole.title)],
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '변경한 제목');
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('미리보기')).dx,
      lessThan(tester.getCenter(find.text('저장')).dx),
    );
    await tester.tap(find.text('미리보기'));
    await tester.pumpAndSettle();
    expect(find.text('변경한 제목'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paragraph-0')))
          .controller!
          .text,
      '변경한 제목',
    );
  });
  testWidgets('RTL assist stays above keyboard and survives scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const ParagraphEditor(
          words: ['كتاب'],
          initial: [
            Paragraph('', ParagraphRole.body),
            Paragraph('second', ParagraphRole.body),
            Paragraph('third', ParagraphRole.body),
          ],
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), 'ك');
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-كتاب')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('assist-popup'))).dy,
      lessThanOrEqualTo(544),
    );
    final popupBefore = tester.getRect(
      find.byKey(const ValueKey('assist-popup')),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('assist-popup'))),
      popupBefore,
    );
    expect(
      tester.getBottomRight(find.byType(ListView).first).dy,
      closeTo(544, 1),
    );
    expect(tester.takeException(), isNull);
  });
}

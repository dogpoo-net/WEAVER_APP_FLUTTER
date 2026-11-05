import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  for (final tag in [false, true]) {
    testWidgets('visible quick assist owns Enter and native submit echoes (tag=$tag)', (tester) async {
      elements.clear(); elements.add('독서 #태그');
      SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
      final storage = WorkspaceStorage(await SharedPreferences.getInstance());
      await tester.pumpWidget(MyApp(storage: storage));
      final field = find.byKey(const ValueKey('quick-memo'));
      final input = tag ? '메모 #태' : '메모 독';
      await tester.enterText(field, input); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-popup')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
      final completed = '메모 ';
      expect(tester.widget<TextField>(field).controller!.text, completed);
      expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done); await tester.pumpAndSettle();
      tester.testTextInput.updateEditingValue(TextEditingValue(text: '$input\n', selection: TextSelection.collapsed(offset: input.length + 1)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, completed);
      expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
      expect(WorkspaceSnapshot.decode(storage.read()!).notes.length, 1);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
  }
  testWidgets('a new Backspace after completion removes the element instead of being treated as an echo', (tester) async {
    elements.clear(); elements.add('독서');
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '독'); await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
  testWidgets('native submit without a hardware key still accepts visible assist first', (tester) async {
    elements.clear(); elements.add('독서');
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '독'); await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(WorkspaceSnapshot.decode(storage.read()!).notes, isEmpty);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
  testWidgets('mobile quick memo displays element and tag assist above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetViewInsets);
    elements.clear(); elements.add('독서 #태그');
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    await tester.pumpWidget(MyApp(storage: WorkspaceStorage(await SharedPreferences.getInstance())));
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '독'); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-독서')), findsOneWidget);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('assist-popup'))).dy, lessThanOrEqualTo(544));
    await tester.enterText(field, '#태'); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggestion-#태그'))); await tester.pumpAndSettle();
    expect(find.byTooltip('#태그 태그 삭제'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

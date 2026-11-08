import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';

void main() {
  testWidgets('mobile keyboard close preserves the draft and closes native input', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MyApp());
    final field = find.byKey(const ValueKey('quick-memo'));
    await tester.enterText(field, '작성 중인 생각 #기록');
    await tester.pumpAndSettle();
    tester.testTextInput.log.clear();
    await tester.tap(find.byTooltip('키보드 내리기'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '작성 중인 생각 #기록');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.log.any((MethodCall call) => call.method == 'TextInput.hide'), isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';

void main() {
  testWidgets('outside touch dismisses ordinary and form fields on any route', (tester) async {
    await tester.pumpWidget(const MyApp(requireLogin: false, ));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    final plain = TextEditingController(text: '일반 입력');
    final form = TextEditingController(text: '폼 입력');
    navigator.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Column(children: [
      TextField(key: const ValueKey('plain'), controller: plain),
      TextFormField(key: const ValueKey('form'), controller: form),
      const Expanded(child: SizedBox.expand(key: ValueKey('outside'))),
    ]))));
    await tester.pumpAndSettle();
    for (final key in ['plain', 'form']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      final editable = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('outside'))));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    }
    expect(plain.text, '일반 입력'); expect(form.text, '폼 입력');
    await tester.pumpWidget(const SizedBox());
    plain.dispose(); form.dispose();
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  testWidgets('mobile keyboard close preserves the draft and closes native input', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MyApp(requireLogin: false, ));
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

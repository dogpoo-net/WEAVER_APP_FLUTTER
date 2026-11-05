import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';

void main() {
  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    testWidgets('quick memo grows within viewport $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
      final field = find.byKey(const ValueKey('quick-memo'));
      final initialHeight = tester.getSize(field).height;
      await tester.enterText(field, List.filled(40, '기록할 생각').join('\n'));
      await tester.pumpAndSettle();
      expect(tester.getSize(field).height, greaterThan(initialHeight));
      expect(tester.getSize(field).height, lessThan(size.height));
      expect(tester.widget<TextField>(field).maxLines, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}

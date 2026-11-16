import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/photo_gallery.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('photo zoom uses full available viewport $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==');
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showPhoto(context, bytes), child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      expect(viewport.width, size.width);
      expect(viewport.bottom, size.height);
      expect(viewport.height, greaterThan(size.height - 100));
      expect(tester.getSize(find.byType(Image)), viewport.size);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

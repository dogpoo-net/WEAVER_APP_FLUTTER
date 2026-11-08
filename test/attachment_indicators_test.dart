import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/attachment_indicators.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/element_store.dart';

void main() {
  testWidgets('only saved attachment kinds receive indicators', (tester) async {
    final record = ElementRecord('사진과 위치');
    expect(AttachmentIndicators.hasAttachments(record), isFalse);
    record.photos.add(PhotoAttachment('photo', 'photo.jpg'));
    record.location = ThoughtLocation(37, 127, 10, DateTime(2026));
    await tester.pumpWidget(MaterialApp(home: AttachmentIndicators(record: record)));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });
}

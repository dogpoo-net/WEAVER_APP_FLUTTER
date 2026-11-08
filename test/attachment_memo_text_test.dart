import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
void main() {
  test('attachment-only titles use local padded timestamp and selected kinds', () {
    expect(attachmentMemoText(DateTime(2026, 1, 1, 13, 13, 13), photos: true, audio: false, location: true),
      '2026-01-01 13:13:13 / 사진, 위치 메모');
    expect(attachmentMemoText(DateTime(2026, 6, 27, 18, 18, 12), photos: false, audio: true, location: false),
      '2026-06-27 18:18:12 / 음성 메모');
  });
}

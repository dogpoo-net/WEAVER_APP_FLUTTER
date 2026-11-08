import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  setUp(elements.clear);
  test('one minute PCM cap generates a playable WAV header even if timer is delayed', () {
    final builder = PcmClipBuilder();
    builder.add(Uint8List(PcmClipBuilder.maxBytes - 2));
    builder.add(Uint8List(16000));
    expect(builder.full, isTrue);
    expect(builder.durationMs, 60000);
    final draft = builder.finish();
    final header = ByteData.sublistView(draft.bytes);
    expect(draft.durationMs, 60000);
    expect(draft.bytes.length, PcmClipBuilder.maxBytes + 44);
    expect(String.fromCharCodes(draft.bytes.take(4)), 'RIFF');
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(40, Endian.little), PcmClipBuilder.maxBytes);
  });
  test('empty recording cannot become an attachment', () {
    expect(() => PcmClipBuilder().finish(), throwsStateError);
  });
  test('coordinates and binary attachment references round trip without embedding media in settings', () {
    final record = elements.add('여행 메모 #여행');
    record.location = ThoughtLocation(37.5665, 126.978, 12, DateTime.utc(2026, 11, 9));
    record.recordings.add(const VoiceAttachment('voice-test', 60000));
    record.photos.addAll(List.generate(5, (i) => PhotoAttachment('photo-$i', '$i.jpg')));
    final snapshot = WorkspaceSnapshot.encode([]);
    WorkspaceSnapshot.decode(snapshot).apply();
    final restored = elements.records['여행 메모']!;
    expect(restored.location!.latitude, 37.5665);
    expect(restored.location!.recordedAt, DateTime.utc(2026, 11, 9));
    expect(restored.recordings.single.durationMs, 60000);
    expect(restored.photos.length, 5);
    expect(restored.tags, {'여행'});
    expect(snapshot.contains('base64'), isFalse);
  });
  test('editing a thought preserves attachment and location identity', () {
    final record = elements.add('수정 전');
    record.location = ThoughtLocation(37, 127, 20, DateTime.utc(2026));
    record.recordings.add(const VoiceAttachment('voice-original', 1200));
    record.photos.add(const PhotoAttachment('photo-original', '사진.jpg'));
    expect(elements.update('수정 전', '수정 후 #사진'), isNull);
    expect(elements.records['수정 후'], same(record));
    expect(record.photos.single.id, 'photo-original');
    expect(record.recordings.single.id, 'voice-original');
    expect(record.location!.longitude, 127);
  });
  test('legacy snapshots have no attachments and invalid coordinates are rejected', () {
    elements.add('기존 생각');
    final snapshot = jsonDecode(WorkspaceSnapshot.encode([])) as Map<String, dynamic>;
    final record = (snapshot['elements'] as List).single as Map<String, dynamic>;
    record.remove('location'); record.remove('recordings'); record.remove('photos');
    final restored = WorkspaceSnapshot.decode(jsonEncode(snapshot)).records.single;
    expect(restored.location, isNull); expect(restored.recordings, isEmpty); expect(restored.photos, isEmpty);
    expect(() => ThoughtLocation.fromJson({'latitude': 91, 'longitude': 0, 'accuracy': 1, 'recordedAt': '2026-11-09'}), throwsFormatException);
  });
}

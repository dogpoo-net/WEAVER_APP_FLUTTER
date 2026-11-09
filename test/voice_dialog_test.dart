import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/capture/voice_dialog.dart';

class FakeRecorder extends RecordPlatform {
  bool permitted = true;
  int stops = 0, cancellations = 0;
  final audio = StreamController<Uint8List>();
  final states = StreamController<RecordState>.broadcast();
  @override
  Future<void> create(String id) async {}
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async => permitted;
  @override
  Stream<RecordState> onStateChanged(String id) => states.stream;
  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig config) async {
    expect(config.sampleRate, 16000); expect(config.numChannels, 1);
    return audio.stream;
  }
  @override
  Future<String?> stop(String id) async {
    stops++;
    // Native stop and EventChannel completion arrive independently.
    unawaited(audio.close());
    return null;
  }
  @override
  Future<void> cancel(String id) async { cancellations++; unawaited(audio.close()); }
  @override
  Future<void> dispose(String id) async { await states.close(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RecordPlatform original;
  late FakeRecorder recorder;
  setUp(() { original = RecordPlatform.instance; recorder = FakeRecorder(); RecordPlatform.instance = recorder; });
  tearDown(() { RecordPlatform.instance = original; });
  testWidgets('permission denial leaves recorder modal cancellable without an attachment', (tester) async {
    recorder.permitted = false;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VoiceRecorderDialog())));
    await tester.tap(find.text('녹음 시작')); await tester.pumpAndSettle();
    expect(find.textContaining('마이크 권한'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '메모에 첨부')).onPressed, isNull);
    expect(recorder.stops, 0);
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
  });
  testWidgets('one minute automatically ends capture and returns WAV only on attach', (tester) async {
    VoiceDraft? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await showVoiceRecorder(context); }, child: const Text('열기'))))));
    await tester.tap(find.text('열기')); await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작')); await tester.pumpAndSettle();
    expect(find.text('녹음 종료'), findsOneWidget);
    recorder.audio.add(Uint8List(PcmClipBuilder.maxBytes));
    await tester.pumpAndSettle();
    expect(recorder.stops, 1);
    expect(result, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '메모에 첨부')).onPressed, isNotNull,
      reason: tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(' | '));
    await tester.tap(find.text('메모에 첨부')); await tester.pumpAndSettle();
    expect(result!.durationMs, 60000);
    expect(String.fromCharCodes(result!.bytes.take(4)), 'RIFF');
    expect(tester.takeException(), isNull);
  });
  testWidgets('outside dismissal during recording cancels capture without an attachment', (tester) async {
    VoiceDraft? result;
    var closed = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await showVoiceRecorder(context); closed = true; }, child: const Text('열기'))))));
    await tester.tap(find.text('열기')); await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작')); await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); await tester.pumpAndSettle();
    expect(find.byType(VoiceRecorderDialog), findsNothing);
    expect(closed, isTrue);
    expect(result, isNull);
    expect(recorder.cancellations, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

}

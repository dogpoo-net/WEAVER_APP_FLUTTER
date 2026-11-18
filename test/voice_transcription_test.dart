import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/capture/voice_transcription.dart';
void main(){
 test('transcript preserves original audio and survives attachment serialization',()async{
  final bytes=Uint8List.fromList([1,2,3]);final draft=VoiceDraft(bytes,12000);
  final result=await transcribeVoice(draft,(action,body)async{
    expect(action,'audio/transcribe');expect(base64Decode(body['data'] as String),bytes);
    return {'text':' 테스트 녹음 ','truncated':true};
  });
  expect(identical(result.bytes,bytes),isTrue);expect(result.durationMs,12000);expect(result.transcript,'테스트 녹음');
  final saved=VoiceAttachment('audio',result.durationMs,transcript:result.transcript);
  expect(VoiceAttachment.fromJson(saved.toJson()).transcript,'테스트 녹음');
 });
 test('failed transcription leaves source draft intact',()async{
  final draft=VoiceDraft(Uint8List.fromList([1]),1000);
  await expectLater(transcribeVoice(draft,(_,body)async=>throw StateError('offline')),throwsStateError);
  expect(draft.bytes,[1]);expect(draft.transcript,isEmpty);
 });
}

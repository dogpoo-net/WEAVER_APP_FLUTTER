import 'dart:convert';
import 'capture_models.dart';
typedef AudioRequest = Future<Map<String,dynamic>> Function(String,Map<String,Object?>);
AudioRequest? voiceAudioRequest;
Future<VoiceDraft> transcribeVoice(VoiceDraft draft, AudioRequest request) async {
  final response=await request('audio/transcribe',{'data':base64Encode(draft.bytes)});
  final text=response['text'];
  if(text is! String)throw StateError('음성 변환 응답을 확인하지 못했습니다.');
  return VoiceDraft(draft.bytes,draft.durationMs,transcript:text.trim());
}

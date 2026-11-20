import 'dart:typed_data';
import '../inbox/element_store.dart';
import '../inbox/workspace_routes.dart';
import 'media_storage.dart';
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

VoiceAttachment attachVoiceDraft(String id, VoiceDraft draft) {
  draft.transcription?.attachmentIds.add(id);
  return VoiceAttachment(id,draft.durationMs,transcript:draft.transcript,transcription:draft.transcription);
}

VoiceDraft beginVoiceTranscription(VoiceDraft draft, AudioRequest request) {
  final job=VoiceTranscriptionJob(), owner=MediaStorage.activeOwner;
  final result=VoiceDraft(draft.bytes,draft.durationMs,transcript:draft.transcript,transcription:job);
  job.completion=()async{
    final converted=await transcribeVoice(draft,request);
    job.text=converted.transcript;
    if(owner!=MediaStorage.activeOwner)return;
    var changed=false;
    for(final record in elements.records.values.toList()){
      for(var i=0;i<record.recordings.length;i++){
        final clip=record.recordings[i];
        if(job.attachmentIds.contains(clip.id) && (identical(clip.transcription,job) || clip.transcript.isEmpty)){
          record.recordings[i]=VoiceAttachment(clip.id,clip.durationMs,transcript:converted.transcript);
          changed=true;
          fillVoiceBody(record);
        }
      }
    }
    if(changed){elements.refreshVisibility();await saveWorkspaceContent?.call();}
  }();
  // The recorder may close before completion. Callers can still await the same
  // future for UI feedback, while detached failures never become unhandled.
  job.completion.catchError((Object _){});
  return result;
}

final _savedRequests=<String,Future<void>>{};
Future<void> retrySavedVoice(String memoId,String audioId,{Future<Uint8List?> Function()? load}) {
  final owner=MediaStorage.activeOwner, key='$owner/$audioId';
  return _savedRequests[key]??= _retrySavedVoice(memoId,audioId,owner,load)
      .whenComplete((){_savedRequests.remove(key);});
}
Future<void> _retrySavedVoice(String memoId,String audioId,String? owner,Future<Uint8List?> Function()? load)async{
  final request=voiceAudioRequest;
  if(request==null)throw StateError('구독 중인 계정으로 로그인해주세요.');
  final active = elements.byId(memoId)?.recordings.where((clip) => clip.id == audioId).firstOrNull;
  if (active?.transcription case final job?) {
    try { await job.completion; return; } catch (_) {}
  }
  final policy=await request('audio/policy',{});
  if(policy['allowed']!=true)throw StateError('AI 텍스트 변환은 구독 중인 계정에서 사용할 수 있습니다.');
  if(policy['enabled']!=true)throw StateError('현재 텍스트 변환을 사용할 수 없습니다.');
  final bytes=await (load==null?MediaStorage.read(audioId,owner:owner):load());
  if(owner!=MediaStorage.activeOwner)throw StateError('워크스페이스가 변경되었습니다.');
  final record=elements.byId(memoId);
  final index=record?.recordings.indexWhere((a)=>a.id==audioId)??-1;
  if(record==null || index<0 || bytes==null)throw StateError('녹음 파일을 찾을 수 없습니다.');
  final clip=record.recordings[index];
  if(clip.transcript.isNotEmpty)return;
  final draft=beginVoiceTranscription(VoiceDraft(bytes,clip.durationMs),request);
  final currentIndex=record.recordings.indexWhere((a)=>a.id==audioId);
  if(currentIndex<0)return;
  record.recordings[currentIndex]=attachVoiceDraft(audioId,draft);
  await draft.transcription!.completion;
}

Future<void> resumePendingVoiceTranscriptions() async {
  if (voiceAudioRequest == null) return;
  final owner = MediaStorage.activeOwner;
  final pending = [
    for (final record in elements.records.values)
      for (final clip in record.recordings)
        if (clip.pendingTranscription && clip.transcription == null)
          (record.id, clip.id),
  ];
  for (final (memoId, audioId) in pending) {
    if (owner != MediaStorage.activeOwner) return;
    try {
      await retrySavedVoice(memoId, audioId);
    } catch (_) {
      // The saved pending record can be retried on the next workspace open.
    }
  }
}

final voiceBodyEditors=<String,int>{};
/// Only generated placeholders can become transcripts; manual text always wins.
bool fillVoiceBody(ElementRecord record){
  if(!record.voiceTextPending || (voiceBodyEditors[record.id]??0)>0)return false;
  final text=record.recordings.map((a)=>a.transcript.trim()).where((t)=>t.isNotEmpty).firstOrNull;
  if(text==null)return false;
  return elements.update(record.text,'음성 추출 텍스트\n$text',tags:Set.of(record.tags),inlineLinks:[])==null;
}

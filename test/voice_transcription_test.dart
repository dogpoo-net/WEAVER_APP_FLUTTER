import 'dart:async';
import 'package:weaver/features/capture/media_storage.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/capture/voice_transcription.dart';
void main(){
 setUp((){elements.clear();elements.onRenamed=null;MediaStorage.activeOwner='owner';voiceBodyEditors.clear();});
 tearDown((){elements.clear();saveWorkspaceContent=null;voiceAudioRequest=null;MediaStorage.activeOwner=null;});
 test('late completion fills voice-only body and persists attached audio',()async{
  final response=Completer<Map<String,dynamic>>();var saves=0;
  saveWorkspaceContent=()async{saves++;};
  final draft=beginVoiceTranscription(VoiceDraft(Uint8List.fromList([1]),1000),(_,body)=>response.future);
  final record=elements.add('음성 메모 시간')..voiceTextPending=true;
  record.recordings.add(attachVoiceDraft('clip',draft));
  expect(record.recordings.single.transcript,isEmpty);
  final saved = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([]));
  expect(saved.records.single.recordings.single.pendingTranscription, isTrue);
  response.complete({'text':'회의 내용'});await draft.transcription!.completion;
  expect(record.text,'음성 추출 텍스트\n회의 내용');expect(record.voiceTextPending,isFalse);
  expect(record.recordings.single.transcript,'회의 내용');expect(saves,1);
  expect(record.recordings.single.pendingTranscription, isFalse);
 });
 test('late completion does not overwrite manual text or deleted audio',()async{
  final response=Completer<Map<String,dynamic>>();
  final draft=beginVoiceTranscription(VoiceDraft(Uint8List(1),1000),(_,body)=>response.future);
  final record=elements.add('자동 제목')..voiceTextPending=true;
  record.recordings.add(attachVoiceDraft('clip',draft));
  elements.update(record.text,'내가 쓴 내용');
  response.complete({'text':'변환 결과'});await draft.transcription!.completion;
  expect(record.text,'내가 쓴 내용');expect(record.recordings.single.transcript,'변환 결과');
  final next=Completer<Map<String,dynamic>>();
  final pending=beginVoiceTranscription(VoiceDraft(Uint8List(1),1000),(_,body)=>next.future);
  record.recordings.add(attachVoiceDraft('removed',pending));record.recordings.removeLast();
  next.complete({'text':'삭제된 녹음'});await pending.transcription!.completion;
  expect(record.recordings.length,1);
 });
 test('completion after workspace switch never saves into the new workspace',()async{
  final response=Completer<Map<String,dynamic>>();var saves=0;saveWorkspaceContent=()async{saves++;};
  final draft=beginVoiceTranscription(VoiceDraft(Uint8List(1),1000),(_,body)=>response.future);
  elements.add('old').recordings.add(attachVoiceDraft('clip',draft));
  MediaStorage.activeOwner='other';elements.clear();final other=elements.add('other');
  other.recordings.add(const VoiceAttachment('clip',1000));
  response.complete({'text':'private'});await draft.transcription!.completion;
  expect(other.recordings.single.transcript,isEmpty);expect(saves,0);
 });
 test('voice body placeholder persists and waits until detail editing closes',(){
  final record=elements.add('자동 제목')..voiceTextPending=true;
  record.recordings.add(const VoiceAttachment('clip',1000,transcript:'결과'));
  final restored=WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).records.single;
  expect(restored.voiceTextPending,isTrue);
  voiceBodyEditors[record.id]=1;expect(fillVoiceBody(record),false);expect(record.text,'자동 제목');
  voiceBodyEditors.clear();expect(fillVoiceBody(record),true);expect(record.text,'음성 추출 텍스트\n결과');
 });
 test('saved retry rechecks subscription before loading or sending audio',()async{
  final calls=<String>[];voiceAudioRequest=(action,body)async{calls.add(action);return {'allowed':false};};
  await expectLater(retrySavedVoice('memo','clip'),throwsStateError);
  expect(calls,['audio/policy']);
 });

 test('saved offline audio retries once and fills body after restart',()async{
  final record=elements.add('음성 메모 시간')..voiceTextPending=true;
  record.recordings.add(const VoiceAttachment('offline',1000));
  final response=Completer<Map<String,dynamic>>();final calls=<String>[];var saves=0;
  saveWorkspaceContent=()async{saves++;};
  voiceAudioRequest=(action,body)async{calls.add(action);if(action=='audio/policy')return {'allowed':true,'enabled':true};return response.future;};
  final first=retrySavedVoice(record.id,'offline',load:()async=>Uint8List.fromList([1]));
  final second=retrySavedVoice(record.id,'offline',load:()async=>throw StateError('duplicate'));
  expect(identical(first,second),isTrue);
  response.complete({'text':'나중에 변환'});await first;
  expect(calls,['audio/policy','audio/transcribe']);expect(saves,1);
  expect(record.text,'음성 추출 텍스트\n나중에 변환');expect(record.recordings.single.transcript,'나중에 변환');
 });
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

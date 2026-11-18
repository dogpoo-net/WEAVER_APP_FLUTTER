import 'recording_file.dart';
import 'voice_transcription.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'capture_models.dart';
import 'voice_player.dart';

Future<VoiceDraft?> showVoiceRecorder(BuildContext context) => showDialog<VoiceDraft>(
  context: context, barrierDismissible: true, builder: (_) => const VoiceRecorderDialog());

class VoiceRecorderDialog extends StatefulWidget {
  const VoiceRecorderDialog({super.key});
  @override
  State<VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}
class _VoiceRecorderDialogState extends State<VoiceRecorderDialog> with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _stream;
  StreamSubscription<RecordState>? _state;
  Completer<void>? _streamDone;
  Timer? _timer;
  PcmClipBuilder _buffer = PcmClipBuilder();
  VoiceDraft? _draft;
  bool _recording = false, _busy = false, _backgrounded = false;
  int _seconds = 0;
  String? _error;
  final AudioRequest? _request = voiceAudioRequest;
  int _maximumSeconds=60;
  late bool _policyLoading=_request!=null;
  bool _transcribing=false, _enabled=false, _allowed=false, _compressed=false;
  String? _filePath;
  final _watch=Stopwatch();
  Future<void> _policy()async{
    try{
      final result=await _request?.call('audio/policy',{});
      if(mounted)setState((){_maximumSeconds=result?['maxRecordingSeconds']==3600?3600:60;_enabled=result?['enabled']==true;_allowed=result?['allowed']==true;});
    }catch(_){if(mounted)setState(()=>_error='변환 서버에 연결하지 못했습니다. 녹음은 기기에 보관할 수 있습니다.');}
    finally{if(mounted)setState(()=>_policyLoading=false);}
  }
  Future<void> _transcribe()async{
    if(_request==null || _draft==null || _transcribing)return;
    final draft=_draft!;
    setState((){_transcribing=true;_error=null;});
    try{
      final converted=await transcribeVoice(draft,_request);
      if(mounted && identical(_draft,draft))setState(()=>_draft=converted);
    }catch(_){if(mounted)setState(()=>_error='텍스트 변환에 실패했습니다. 다시 시도하거나 녹음만 첨부할 수 있습니다.');}
    finally{if(mounted)setState(()=>_transcribing=false);}
  }
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);_policy();
    _state = _recorder.onStateChanged().listen((state) {
      if (_recording && state != RecordState.record) unawaited(_stop());
    });
  }
  Future<void> _start() async {
    if (_busy || _recording) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _recorder.hasPermission()) throw StateError('마이크 권한을 허용해주세요.');
      if (!mounted || _backgrounded) return;
      _compressed=false;
      for(final encoder in [AudioEncoder.aacLc,AudioEncoder.opus]){
        if(await _recorder.isEncoderSupported(encoder)){
          _filePath=await recordingPath();
          await _recorder.start(RecordConfig(encoder:encoder,bitRate:48000,sampleRate:16000,numChannels:1),path:_filePath!);
          _compressed=true;break;
        }
      }
      if(!mounted || _backgrounded){await _recorder.cancel();return;}
      if(_compressed){
        setState((){_recording=true;_seconds=0;_draft=null;});
      }else{
        _maximumSeconds=60;
      _buffer = PcmClipBuilder(); _streamDone = Completer<void>();
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: PcmClipBuilder.sampleRate, numChannels: 1));
      if (!mounted || _backgrounded) { await _recorder.cancel(); return; }
      setState(() { _recording = true; _seconds = 0; _draft = null; });
      _stream = stream.listen((chunk) {
        _buffer.add(chunk);
        if (_buffer.full) unawaited(_stop());
      }, onError: (Object error) {
        if (mounted) setState(() => _error = '녹음이 중단되었습니다. 다시 시도해주세요.');
        unawaited(_stop());
      }, onDone: () { if (!_streamDone!.isCompleted) _streamDone!.complete(); if (_recording) unawaited(_stop()); });
      }
      _watch..reset()..start();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _seconds = _watch.elapsed.inSeconds.clamp(0, _maximumSeconds));
        if (_watch.elapsed >= Duration(seconds:_maximumSeconds)) unawaited(_stop());
      });
    } catch (_) {
      if (mounted) setState(() => _error = '녹음을 시작할 수 없습니다. 마이크 권한과 다른 앱의 마이크 사용 여부를 확인해주세요.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _stop() async {
    if (!_recording || _busy) return;
    _timer?.cancel();
    setState(() { _busy = true; _recording = false; });
    try {
      _watch.stop();
      final path=await _recorder.stop().timeout(const Duration(seconds: 10));
      if(_compressed){
        if(path==null)throw StateError('녹음 파일이 없습니다.');
        final bytes=await finishRecordingFile(path);_filePath=null;
        if(bytes.isEmpty || bytes.length>32*1024*1024)throw StateError('녹음 파일 크기 한도를 초과했습니다.');
        if(mounted)setState(()=>_draft=VoiceDraft(bytes,_watch.elapsedMilliseconds));
      }else{
      await _streamDone?.future.timeout(const Duration(seconds: 2));
      // onDone has already closed this subscription. Cancelling it again can
      // wait on the same close operation that delivered the completion event.
      _stream = null;
      final draft = _buffer.finish();
      if (mounted) setState(() => _draft = draft);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '녹음을 완료하지 못했습니다. 다시 녹음해주세요.');
    } finally { if (mounted) setState(() => _busy = false); }
    if(mounted && _enabled && _draft!=null)await _transcribe();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _backgrounded = false;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _backgrounded = true; unawaited(_stop());
    }
  }
  Future<void> _releaseRecorder() async {
    try { await _recorder.cancel(); } catch (_) { /* Nothing may have started. */ }
    await _recorder.dispose();
    if(_filePath!=null)await discardRecordingPath(_filePath!);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); _stream?.cancel(); _state?.cancel(); unawaited(_releaseRecorder()); super.dispose();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Row(children: [const Expanded(child: Text('음성 메모')), Text(_maximumSeconds==3600?'최대 1시간':'최대 1분', style: Theme.of(context).textTheme.labelSmall)]),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_recording ? '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')} / ${_maximumSeconds==3600?'60:00':'01:00'}' : '00:00', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      if (_busy || _policyLoading || _transcribing) const Padding(padding: EdgeInsets.only(bottom: 12),
        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      if (_draft != null) VoicePlayer(key: ObjectKey(_draft), load: () async => _draft!.bytes, durationMs: _draft!.durationMs),
      if(_draft?.transcript.isNotEmpty??false)ConstrainedBox(constraints:const BoxConstraints(maxHeight:160),child:SingleChildScrollView(child:SelectableText(_draft!.transcript))),
      if(_request==null)const Text('AI 텍스트 변환은 구독 중인 계정으로 로그인 후 사용할 수 있습니다.')
      else if(!_allowed)const Text('AI 텍스트 변환은 구독 중인 계정에서 사용할 수 있습니다.')
      else if(!_enabled)const Text('현재 텍스트 변환을 사용할 수 없습니다. 녹음은 첨부할 수 있습니다.')
      else const Text('녹음 종료 후 전체 내용을 텍스트로 변환합니다.'),
      if(_transcribing)const Text('텍스트로 변환하고 있습니다…'),
      if(_enabled && _draft!=null && !_recording)TextButton(onPressed:_transcribing?null:_transcribe,child:const Text('텍스트 변환 다시 시도')),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      FilledButton.tonalIcon(onPressed: _busy || _policyLoading || _transcribing ? null : (_recording ? _stop : _start),
        icon: Icon(_recording ? Icons.stop : Icons.mic), label: Text(_recording ? '녹음 종료' : _draft == null ? '녹음 시작' : '다시 녹음')),
    ]),
    actions: [
      TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12)), onPressed: () => Navigator.pop(context), child: const Text('취소')),
      FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12)), onPressed: _busy || _transcribing || _recording || _draft == null ? null : () => Navigator.pop(context, _draft), child: const Text('메모에 첨부')),
    ],
  );
}

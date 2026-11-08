import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'capture_models.dart';
import 'voice_player.dart';

Future<VoiceDraft?> showVoiceRecorder(BuildContext context) => showDialog<VoiceDraft>(
  context: context, barrierDismissible: false, builder: (_) => const VoiceRecorderDialog());

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
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
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
      final watch = Stopwatch()..start();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _seconds = watch.elapsed.inSeconds.clamp(0, 60));
        if (watch.elapsed >= const Duration(minutes: 1)) unawaited(_stop());
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
      await _recorder.stop().timeout(const Duration(seconds: 5));
      await _streamDone?.future.timeout(const Duration(seconds: 2));
      // onDone has already closed this subscription. Cancelling it again can
      // wait on the same close operation that delivered the completion event.
      _stream = null;
      final draft = _buffer.finish();
      if (mounted) setState(() => _draft = draft);
    } catch (_) {
      if (mounted) setState(() => _error = '녹음을 완료하지 못했습니다. 다시 녹음해주세요.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _backgrounded = false;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _backgrounded = true; unawaited(_stop());
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); _stream?.cancel(); _state?.cancel(); _recorder.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy && !_recording, child: AlertDialog(
    title: const Text('녹음 메모'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_recording ? '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')} / 01:00' : '최대 1분', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12),
        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      if (_draft != null) VoicePlayer(key: ObjectKey(_draft), load: () async => _draft!.bytes, durationMs: _draft!.durationMs),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      FilledButton.tonalIcon(onPressed: _busy ? null : (_recording ? _stop : _start),
        icon: Icon(_recording ? Icons.stop : Icons.mic), label: Text(_recording ? '녹음 종료' : _draft == null ? '녹음 시작' : '다시 녹음')),
    ]),
    actions: [
      TextButton(onPressed: _busy ? null : () async {
        if (_recording) await _stop();
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('취소')),
      FilledButton(onPressed: _busy || _recording || _draft == null ? null : () => Navigator.pop(context, _draft), child: const Text('메모에 첨부')),
    ],
  ));
}

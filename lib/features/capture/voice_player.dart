import 'capture_models.dart';
import 'playback_source.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, this.dialogLayout = false, required this.load, required this.durationMs,this.textStyle,this.transcript='',this.onTranscribe,this.transcription,this.trailing,this.actionStyle});
  final Future<Uint8List?> Function() load;
  final bool dialogLayout;
  final int durationMs;
  final String transcript;
  final Widget? trailing;
  final ButtonStyle? actionStyle;
  final VoiceTranscriptionJob? transcription;
  final Future<void> Function()? onTranscribe;
  final TextStyle? textStyle;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}
class _VoicePlayerState extends State<VoicePlayer> {
  AudioPlayer? _player;
  PlaybackSource? _playbackSource;
  StreamSubscription<void>? _completed;
  bool _playing = false, _busy = false;
  String? _error, _transcriptionError;
  bool _transcribing=false, _showTranscript=false;
  Future<void> _transcribe()async{
    if(_transcribing || widget.onTranscribe==null)return;
    setState((){_transcribing=true;_transcriptionError=null;});
    try{await widget.onTranscribe!();}catch(e){if(mounted)setState(()=>_transcriptionError='텍스트 변환을 완료하지 못했습니다. $e');}
    finally{if(mounted)setState(()=>_transcribing=false);}
  }
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_playing) {
        await _player?.stop();
        if (mounted) setState(() => _playing = false);
      } else {
        final bytes = await widget.load();
        if (!mounted) return;
        if (bytes == null) throw StateError('오디오 파일을 찾을 수 없습니다.');
        if (_player == null) {
          _player = AudioPlayer();
          _completed = _player!.onPlayerComplete.listen((_) { if (mounted) setState(() => _playing = false); });
        }
        if (_playbackSource == null) {
          final source = await PlaybackSource.create(bytes);
          if (!mounted) { await source.dispose(); return; }
          _playbackSource = source;
        }
        await _player!.play(_playbackSource!.source);
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '녹음 파일을 재생하지 못했습니다.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _release() async {
    try { await _player?.dispose(); } finally { await _playbackSource?.dispose(); }
  }
  @override
  void dispose() { _completed?.cancel(); unawaited(_release()); super.dispose(); }
  static final _compact=TextButton.styleFrom(minimumSize:const Size(0,28),padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),tapTargetSize:MaterialTapTargetSize.shrinkWrap,visualDensity:VisualDensity.compact,textStyle:const TextStyle(fontSize:12));
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: widget.transcription?.completion,
    builder: (context, snapshot) {
      final transcript = widget.transcription?.text ?? widget.transcript;
      final inlineActions = widget.trailing != null;
      final toggleLabel = _showTranscript ? '변환된 텍스트 접기' : '변환된 텍스트 펼치기';
      final duration = Text(
        widget.durationMs == 0 ? '음성 파일' : '음성 메모 · ${(widget.durationMs / 1000).ceil()}초',
        style: widget.textStyle ?? Theme.of(context).textTheme.bodySmall,
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: inlineActions ? MainAxisSize.max : MainAxisSize.min, children: [
          IconButton(
            style: widget.actionStyle,
            tooltip: _playing ? '녹음 재생 중지' : '녹음 재생',
            onPressed: _busy ? null : _toggle,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_playing ? Icons.stop : Icons.play_arrow),
          ),
          if (inlineActions) Expanded(child: duration) else Flexible(child: duration),
          if (inlineActions && transcript.isNotEmpty) IconButton(
            style: widget.actionStyle,
            tooltip: toggleLabel,
            isSelected: _showTranscript,
            icon: const Icon(Icons.text_snippet_outlined),
            selectedIcon: const Icon(Icons.text_snippet),
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
          ),
          if (widget.trailing case final trailing?) trailing,
        ]),
        if (transcript.isEmpty && widget.onTranscribe != null) TextButton.icon(
          style: _compact,
          onPressed: _transcribing ? null : _transcribe,
          icon: _transcribing
              ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.text_snippet_outlined, size: 18),
          label: Text(_transcribing ? '텍스트 변환 중…' : '텍스트 변환'),
        ),
        if (_transcriptionError != null)
          Text(_transcriptionError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        if (transcript.isNotEmpty) ...[
          if (!inlineActions) TextButton.icon(
            style: widget.dialogLayout ? TextButton.styleFrom(padding: const EdgeInsets.only(right: 8), alignment: Alignment.centerLeft) : _compact,
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
            icon: Icon(_showTranscript ? Icons.expand_less : Icons.expand_more, size: 16),
            label: const Text('변환된 텍스트'),
          ),
          if (_showTranscript && widget.dialogLayout) Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4), child: SelectableText(transcript)),
          if (_showTranscript && !widget.dialogLayout) SizedBox(width: double.infinity, child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 8, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)),
              SelectableText(transcript),
              Divider(height: 8, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)),
            ],
          )),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
      ]);
    },
  );
}

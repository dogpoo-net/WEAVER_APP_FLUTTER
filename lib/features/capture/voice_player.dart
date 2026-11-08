import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.load, required this.durationMs});
  final Future<Uint8List?> Function() load;
  final int durationMs;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}
class _VoicePlayerState extends State<VoicePlayer> {
  AudioPlayer? _player;
  StreamSubscription<void>? _completed;
  bool _playing = false, _busy = false;
  String? _error;
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
        await _player!.play(BytesSource(bytes, mimeType: 'audio/wav'));
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '녹음 파일을 재생하지 못했습니다.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() { _completed?.cancel(); _player?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: _playing ? '녹음 재생 중지' : '녹음 재생', onPressed: _busy ? null : _toggle,
        icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_playing ? Icons.stop : Icons.play_arrow)),
      Text('음성 메모 · ${(widget.durationMs / 1000).ceil()}초', style: Theme.of(context).textTheme.bodySmall),
    ]),
    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
  ]);
}

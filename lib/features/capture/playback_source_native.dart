import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
class PlaybackSource {
  PlaybackSource._(this.source, this._directory);
  final Source source;
  final Directory _directory;
  static Future<PlaybackSource> create(Uint8List bytes) async {
    final directory = await (await getTemporaryDirectory()).createTemp('weaver-voice-');
    try {
      final file = File('${directory.path}/memo.wav');
      await file.writeAsBytes(bytes);
      return PlaybackSource._(DeviceFileSource(file.path, mimeType: 'audio/wav'), directory);
    } catch (_) { await directory.delete(recursive: true); rethrow; }
  }
  Future<void> dispose() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}

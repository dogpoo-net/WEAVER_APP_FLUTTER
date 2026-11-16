import 'audio_format.dart';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
class PlaybackSource {
  PlaybackSource._(this.source);
  final Source source;
  static Future<PlaybackSource> create(Uint8List bytes) async => PlaybackSource._(BytesSource(bytes, mimeType: audioMime(bytes)));
  Future<void> dispose() async {}
}

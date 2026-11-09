import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
class PlaybackSource {
  PlaybackSource._(this.source);
  final Source source;
  static Future<PlaybackSource> create(Uint8List bytes) async => PlaybackSource._(BytesSource(bytes, mimeType: 'audio/wav'));
  Future<void> dispose() async {}
}

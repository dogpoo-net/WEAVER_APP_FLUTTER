import 'dart:typed_data';

class ThoughtLocation {
  const ThoughtLocation(this.latitude, this.longitude, this.accuracy, this.recordedAt);
  final double latitude, longitude, accuracy;
  final DateTime recordedAt;
  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude,
    'accuracy': accuracy, 'recordedAt': recordedAt.toIso8601String()};
  static ThoughtLocation? fromJson(dynamic json) {
    if (json == null) return null;
    final lat = (json['latitude'] as num).toDouble(), lon = (json['longitude'] as num).toDouble();
    final accuracy = (json['accuracy'] as num).toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180 || !accuracy.isFinite || accuracy < 0) {
      throw const FormatException('Invalid thought location');
    }
    return ThoughtLocation(lat, lon, accuracy, DateTime.parse(json['recordedAt'] as String));
  }
}

class VoiceAttachment {
  const VoiceAttachment(this.id, this.durationMs);
  final String id;
  final int durationMs;
  Map<String, dynamic> toJson() => {'id': id, 'durationMs': durationMs};
  factory VoiceAttachment.fromJson(dynamic json) {
    final id = json['id'] as String, duration = json['durationMs'] as int;
    if (id.isEmpty || duration <= 0 || duration > 60000) throw const FormatException('Invalid voice attachment');
    return VoiceAttachment(id, duration);
  }
}

class VoiceDraft {
  const VoiceDraft(this.bytes, this.durationMs);
  final Uint8List bytes;
  final int durationMs;
}

/// Mono signed 16-bit PCM at 16 kHz. The byte limit also enforces one minute
/// when timers are delayed by a backgrounded browser.
class PcmClipBuilder {
  static const sampleRate = 16000, maxBytes = sampleRate * 2 * 60;
  final _bytes = BytesBuilder(copy: false);
  bool get full => _bytes.length >= maxBytes;
  int get durationMs => _bytes.length * 1000 ~/ (sampleRate * 2);
  void add(Uint8List chunk) {
    final remaining = maxBytes - _bytes.length;
    if (remaining <= 0) return;
    _bytes.add(chunk.length <= remaining ? chunk : Uint8List.sublistView(chunk, 0, remaining));
  }
  VoiceDraft finish() {
    final pcm = _bytes.takeBytes();
    final length = pcm.length - pcm.length % 2;
    if (length < sampleRate / 5) throw StateError('녹음이 너무 짧습니다. 다시 녹음해주세요.');
    final wav = Uint8List(44 + length), header = ByteData(44);
    void text(int offset, String value) { wav.setRange(offset, offset + value.length, value.codeUnits); }
    header.setUint32(4, 36 + length, Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little); header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little); header.setUint16(34, 16, Endian.little);
    header.setUint32(40, length, Endian.little);
    wav.setRange(0, 44, header.buffer.asUint8List());
    text(0, 'RIFF'); text(8, 'WAVE'); text(12, 'fmt '); text(36, 'data');
    wav.setRange(44, wav.length, pcm);
    return VoiceDraft(wav, length * 1000 ~/ (sampleRate * 2));
  }
}

class PhotoAttachment {
  const PhotoAttachment(this.id, this.name);
  final String id, name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory PhotoAttachment.fromJson(dynamic json) {
    final id = json['id'] as String;
    if (id.isEmpty) throw const FormatException('Invalid photo attachment');
    return PhotoAttachment(id, json['name'] as String? ?? '사진');
  }
}
class PhotoDraft {
  const PhotoDraft(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

String attachmentMemoText(DateTime createdAt, {required bool photos, required bool audio, required bool location}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final time = createdAt.toLocal();
  final kinds = [if (photos) '사진', if (audio) '음성', if (location) '위치'];
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)} / ${kinds.join(',')} 메모';
}

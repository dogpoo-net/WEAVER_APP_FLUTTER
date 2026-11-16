import 'dart:typed_data';
String audioMime(Uint8List bytes) {
 bool has(int at,String value)=>bytes.length>=at+value.length && String.fromCharCodes(bytes.sublist(at,at+value.length))==value;
 if(has(0,'RIFF')&&has(8,'WAVE'))return 'audio/wav';
 if(has(0,'ID3') || bytes.length>=2 && bytes[0]==255 && bytes[1]&224==224)return 'audio/mpeg';
 if(has(4,'ftyp'))return 'audio/mp4';
 if(has(0,'OggS'))return 'audio/ogg';
 if(has(0,'fLaC'))return 'audio/flac';
 if(bytes.length>=4 && bytes[0]==0x1a && bytes[1]==0x45 && bytes[2]==0xdf && bytes[3]==0xa3)return 'audio/webm';
 throw const FormatException('지원하지 않는 음성 파일입니다. WAV, MP3, M4A, OGG, FLAC, WebM 파일을 선택해주세요.');
}
String audioExtension(String mime)=>{'audio/wav':'wav','audio/mpeg':'mp3','audio/mp4':'m4a','audio/ogg':'ogg','audio/flac':'flac','audio/webm':'webm'}[mime]!;

import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:audioplayers/audioplayers.dart';
import 'capture_models.dart';
import 'audio_format.dart';
import 'playback_source.dart';

Future<List<PhotoDraft>> pickPhotoUploads(int remaining) async {
 if(remaining<=0)throw StateError('사진은 최대 5장까지 저장할 수 있습니다.');
 final picker=ImagePicker();
 final List<XFile> files;
 if(remaining==1){final file=await picker.pickImage(source:ImageSource.gallery,maxWidth:2048,maxHeight:2048,imageQuality:85);files=file==null?[]:[file];}
 else{files=await picker.pickMultiImage(limit:remaining,maxWidth:2048,maxHeight:2048,imageQuality:85);}
 final result=<PhotoDraft>[];
 for(final file in files.take(remaining)){
  if(await file.length()>10*1024*1024)throw StateError('사진 한 장은 10MB 이하로 선택해주세요.');
  result.add(PhotoDraft(await file.readAsBytes(),file.name));
 }
 return result;
}
Future<VoiceDraft?> pickAudioUpload() async {
 final file=await openFile(acceptedTypeGroups:[const XTypeGroup(label:'음성 파일',extensions:['wav','mp3','m4a','ogg','flac','webm'],mimeTypes:['audio/*'],uniformTypeIdentifiers:['public.audio'])]);
 if(file==null)return null;
 if(await file.length()>10*1024*1024)throw StateError('음성 파일은 10MB 이하로 선택해주세요.');
 final bytes=await file.readAsBytes();audioMime(bytes);
 final source=await PlaybackSource.create(bytes);final player=AudioPlayer();
 var duration=0;
 try {await player.setSource(source.source).timeout(const Duration(seconds:10));duration=(await player.getDuration())?.inMilliseconds??0;}
 catch(_){ /* Some platforms cannot determine duration until playback starts. */ }
 finally{await player.dispose();await source.dispose();}
 if(duration<0)duration=0;
 if(duration>86400000)throw StateError('24시간 이하의 음성 파일을 선택해주세요.');
 return VoiceDraft(bytes,duration);
}

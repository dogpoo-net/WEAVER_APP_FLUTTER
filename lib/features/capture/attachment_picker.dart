import 'package:image_picker/image_picker.dart';
import 'capture_models.dart';

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

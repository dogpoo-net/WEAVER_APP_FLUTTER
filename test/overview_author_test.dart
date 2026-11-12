import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/overview_collections.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 test('Own authorship uses account identity; unknown shared authors are not labelled as me',()async{
  SharedPreferences.setMockInitialValues({});final s=WorkspaceStorage(await SharedPreferences.getInstance(),owner:'account@workspace:shared')..currentUserId='me';
  s.itemMetadata=(_,id)=>{'authorId':'me','author':''};expect(overviewAuthor(s,'list:notes','n'),'나');
  s.itemMetadata=(_,id)=>{'authorId':'someone','author':'팀원'};expect(overviewAuthor(s,'list:notes','n'),'팀원');
  s.itemMetadata=(_,id)=>{'authorId':null,'author':null};expect(overviewAuthor(s,'list:notes','n'),'작성자 정보 없음');
  s.itemMetadata=(_,id)=>null;expect(overviewAuthor(s,'list:notes','local-new'),'나');
 });
}

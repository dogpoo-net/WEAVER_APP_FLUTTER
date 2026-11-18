import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
void main(){
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('combined write preserves backup and layouts and notifies only once',()async{
  final p=await SharedPreferences.getInstance();final s=WorkspaceStorage(p,owner:'account/workspace');
  const before='{"version":1,"elements":[]}';
  await s.write(before);var changes=0;s.onChanged=()=>changes++;
  const next='{"version":1,"elements":[],"graphLayout":{"positions":{"a":[1,2]}}}';
  const graphs='{"page":{"positions":{"a":[1,2]}},"boxes":{}}';
  await s.write(next,graphLayouts:graphs);await s.flush();
  expect(s.read(),next);expect(s.readGraphLayouts(),graphs);
  expect(p.getString('${s.workspaceKey}.previous'),before);expect(changes,1);
  await s.write(next,graphLayouts:graphs);expect(changes,1);
  expect(WorkspaceStorage(p,owner:'other').read(),isNull);
 });
 test('same draft does not notify again and saved marker replaces it',()async{
  final s=WorkspaceStorage(await SharedPreferences.getInstance());
  await s.writeDocumentDraft('doc',{'text':'draft','links':[]});
  final count=s.documentDraftChanges.value;
  await s.writeDocumentDraft('doc',{'text':'draft','links':[]});
  expect(s.documentDraftChanges.value,count);
  await s.writeDocumentDraft('doc',null);expect(s.documentDraft('doc'),isNull);
  s.suspended=true;
  await expectLater(s.writeDocumentDraft('doc',null),throwsStateError);
 });
 test('benchmark redundant layout rewrite for a 5000 memo snapshot',(){
  final data={'version':1,'elements':List.generate(5000,(i)=>{'id':'memo-$i','text':'생각 내용 $i ${'본문 ' * 40}','tags':['tag'],'photos':[],'recordings':[]}), 'memoBoxes':[], 'graphLayout':{'positions':{}}};
  final raw=jsonEncode(data);final layout=jsonEncode({'page':{'positions':{}},'boxes':{}});
  final times=<int>[];
  for(var i=0;i<7;i++){
   final watch=Stopwatch()..start();
   final decoded=jsonDecode(raw) as Map<String,dynamic>;
   decoded['graphLayout']=(jsonDecode(layout) as Map)['page'];
   final updated=jsonEncode(decoded);watch.stop();expect(updated,raw);times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  // Reporting CPU removed from each combined write, not browser FPS.
  // ignore: avoid_print
  print('snapshot UTF8 bytes=${utf8.encode(raw).length}; redundant decode+encode median=${times[3]/1000}ms');
 });
}

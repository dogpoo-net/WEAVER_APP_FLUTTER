import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/document_merge.dart';
Map<String,dynamic> note(String text,{List<Map<String,dynamic>> links=const []})=>{'id':'n','content':text,'project':{'id':'p','document':text,'documentLinks':links,'tags':[],'name':'doc','words':[],'paragraphs':[]}};
void main(){
 test('different edited lines and inserted lines merge',(){
  final plan=mergeDocument(note('a\nb\nc\n'),note('A\nb\nc\n'),note('a\nb\nnew\nc\n'));
  expect(plan.hasConflicts,false);expect(documentSegment(plan.resolve()).text,'A\nb\nnew\nc\n');
 });
 test('same edits merge once',(){final p=mergeDocument(note('a\nb'),note('a\nB'),note('a\nB'));expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).text,'a\nB');});
 test('different changes on same line require explicit resolution',(){
  final p=mergeDocument(note('a\nb\nc'),note('a\nB\nc'),note('a\nother\nc'));expect(p.hasConflicts,true);
  final index=p.parts.indexWhere((v)=>v.conflict);expect(p.parts[index].firstLine,2);
  expect(documentSegment(p.resolve({index:p.parts[index].remote})).text,'a\nother\nc');
 });
 test('delete versus edit and insert at same boundary conflict',(){
  expect(mergeDocument(note('a\nb\nc'),note('a\nc'),note('a\nB\nc')).hasConflicts,true);
  expect(mergeDocument(note('a\nb'),note('a\nx\nb'),note('a\ny\nb')).hasConflicts,true);
 });
 test('different lines preserve link targets and shift offsets including Korean and emoji',(){
  final p=mergeDocument(note('첫줄\n링크\n끝'),note('😀 첫줄\n링크\n끝'),note('첫줄\n링크\n끝!',links:[{'id':'project:x','start':3,'end':5}]));
  expect(p.hasConflicts,false);final result=documentSegment(p.resolve());expect(result.text,'😀 첫줄\n링크\n끝!');expect(result.links.single.id,'project:x');expect(result.links.single.start,6);expect(result.links.single.end,8);
 });
 test('same link title changed to different targets conflicts',(){
  final p=mergeDocument(note('링크'),note('링크',links:[{'id':'project:a','start':0,'end':2}]),note('링크',links:[{'id':'project:b','start':0,'end':2}]));expect(p.hasConflicts,true);
 });
 test('multi-line links are atomic and tables preserve row changes',(){
  final text='one\ntwo\nthree';final links=[{'id':'project:a','start':0,'end':7}];
  final p=mergeDocument(note(text,links:links),note('$text!',links:links),note('zero\n$text',links:[{'id':'project:a','start':5,'end':12}]));expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).links.single.start,5);
  final table=mergeDocument(note('| a |\n| b |\n| c |'),note('| A |\n| b |\n| c |'),note('| a |\n| b |\n| C |'));expect(table.hasConflicts,false);expect(documentSegment(table.resolve()).text,'| A |\n| b |\n| C |');
 });
 test('unrelated remote changes remain when a conflicting line is resolved',(){
  final p=mergeDocument(note('a\nb\nc'),note('A\nb\nc'),note('other\nb\nC'));final choices={for(var i=0;i<p.parts.length;i++)if(p.parts[i].conflict)i:p.parts[i].mine};expect(documentSegment(p.resolve(choices)).text,'A\nb\nC');
 });
}

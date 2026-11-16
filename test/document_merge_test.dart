import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/document_merge.dart';
Map<String,dynamic> note(String text,{List<Map<String,dynamic>> links=const []})=>{'id':'n','content':text,'project':{'id':'p','document':text,'documentLinks':links,'tags':[],'name':'doc','words':[],'paragraphs':[]}};
void main(){
 test('different edited lines and inserted lines merge',(){
  final plan=mergeDocument(note('a\nb\nc\n'),note('A\nb\nc\n'),note('a\nb\nnew\nc\n'));
  expect(plan.hasConflicts,false);expect(documentSegment(plan.resolve()).text,'A\nb\nnew\nc\n');
 });
 test('insert before the last line and append after it are independent',(){
  for(final swap in [false,true]){
   final left=note('첫 줄\n앞에 추가\n마지막 줄'),right=note('첫 줄\n마지막 줄\n뒤에 추가');
   final p=mergeDocument(note('첫 줄\n마지막 줄'),swap?right:left,swap?left:right);
   expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).text,'첫 줄\n앞에 추가\n마지막 줄\n뒤에 추가');
  }
 });
 test('inserting before a line does not conflict with editing that line',(){
  final p=mergeDocument(note('a\nb\nc'),note('a\nnew\nb\nc'),note('a\nB\nc'));
  expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).text,'a\nnew\nB\nc');
 });
 test('append after the final line merges with editing the final line',(){
  final p=mergeDocument(note('a\nb'),note('a\nb\nnew'),note('a\nB'));
  expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).text,'a\nB\nnew');
 });
 test('large sparse independent insertions do not become a whole-document conflict',(){
  final lines=List.generate(1600,(i)=>'line $i');final left=List<String>.of(lines)..insert(1599,'late local')..insert(1,'early local');final right=List<String>.of(lines)..insert(800,'remote');
  final p=mergeDocument(note(lines.join('\n')),note(left.join('\n')),note(right.join('\n')));
  expect(p.hasConflicts,false);final expected=List<String>.of(lines)..insert(1599,'late local')..insert(800,'remote')..insert(1,'early local');expect(documentSegment(p.resolve()).text,expected.join('\n'));
 });
 test('single-sided insertions preserve exact trailing newlines and links',(){
  for(final original in ['', 'a', 'a\n', 'a\n\n']){
   for(final edited in ['new\n$original','$original\nnew','$original\nnew\n']){
    final p=mergeDocument(note(original),note(edited),note(original));expect(p.hasConflicts,false);expect(documentSegment(p.resolve()).text,edited);
   }
  }
  final p=mergeDocument(note('a\nb'),note('a\nb\nlink',links:[{'id':'project:x','start':4,'end':8}]),note('A\nb'));
  expect(p.hasConflicts,false);final result=documentSegment(p.resolve());expect(result.text,'A\nb\nlink');expect(result.links.single.start,4);expect(result.links.single.end,8);
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

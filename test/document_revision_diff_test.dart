import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/document_revision_diff.dart';
void main() {
 test('replacement preserves context and both line numbers', () {
  final rows=revisionLines([
   {'operation':'equal','text':'문단 하나\n문장 '},
   {'operation':'delete','text':'이전'}, {'operation':'insert','text':'새😀'},
   {'operation':'equal','text':'입니다.\n마지막'},
  ]);
  expect(rows.map((r)=>r.operation),['equal','delete','insert','equal']);
  expect(rows.map((r)=>r.text),['문단 하나','문장 이전입니다.','문장 새😀입니다.','마지막']);
  expect(rows[1].before,2);expect(rows[2].after,2);expect(rows[3].before,3);expect(rows[3].after,3);
  expect(rows[2].parts.where((p)=>p.changed).single.text,'새😀');
 });
 test('whole paragraphs and blank lines retain added and deleted rows', () {
  final rows=revisionLines([{'operation':'equal','text':'앞\n'}, {'operation':'delete','text':'삭제\n\n'}, {'operation':'insert','text':'새 문단\n'}, {'operation':'equal','text':'뒤'}]);
  expect(rows.where((r)=>r.before!=null).map((r)=>r.text).join('\n'),'앞\n삭제\n\n뒤');
  expect(rows.where((r)=>r.after!=null).map((r)=>r.text).join('\n'),'앞\n새 문단\n뒤');
 });
 test('a removed newline is not marked unchanged',(){
  final rows=revisionLines([{'operation':'equal','text':'끝'},{'operation':'delete','text':'\n'}]);
  expect(rows.map((r)=>r.operation),['delete','insert']);
 });
}

import 'dart:convert';
import 'dart:typed_data';
import '../inbox/document_markup.dart';
import '../inbox/element_binding.dart';

class DocumentSegment {
  DocumentSegment(this.text,this.links);
  final String text;
  final List<ElementBinding> links;
  String get signature=>jsonEncode([text,links.map((b)=>b.toJson()).toList()]);
  static DocumentSegment join(Iterable<DocumentSegment> parts){
    final text=StringBuffer(),links=<ElementBinding>[];var offset=0;
    for(final part in parts){links.addAll(part.links.map((b)=>ElementBinding(b.id,b.start+offset,b.end+offset)));text.write(part.text);offset+=part.text.length;}
    return DocumentSegment(text.toString(),links);
  }
}
DocumentSegment documentSegment(Map<String,dynamic> note){
  final project=note['project'] as Map;
  final text=project['document'] as String? ?? (project['paragraphs'] as List? ?? []).map((p)=>p['text']).join('\n\n');
  final links=[for(final b in project['documentLinks'] as List? ?? [])if(b['start'] is int && b['end'] is int && b['start']>=0 && b['end']<=text.length && b['start']<b['end'])ElementBinding(b['id'] as String,b['start'] as int,b['end'] as int)]..sort((a,b)=>a.start.compareTo(b.start));
  return DocumentSegment(text,links);
}
List<DocumentSegment> _lines(DocumentSegment source){
  final boundaries=<int>[0];
  for(var i=0;i<source.text.length;i++){
    if(source.text[i]=='\n'&&!source.links.any((b)=>b.start<i+1&&b.end>i+1))boundaries.add(i+1);
  }
  if(boundaries.last!=source.text.length)boundaries.add(source.text.length);
  return [for(var i=0;i+1<boundaries.length;i++)DocumentSegment(source.text.substring(boundaries[i],boundaries[i+1]),[for(final b in source.links)if(b.start>=boundaries[i]&&b.end<=boundaries[i+1])ElementBinding(b.id,b.start-boundaries[i],b.end-boundaries[i])])];
}
class _Edit {
  _Edit(this.start,this.end,this.lines,this.mine);
  final int start,end;final List<DocumentSegment> lines;final bool mine;
}
List<_Edit> _edits(List<DocumentSegment> base,List<DocumentSegment> next,bool mine){
  final a=base.map((s)=>s.signature).toList(),b=next.map((s)=>s.signature).toList();
  var prefix=0;while(prefix<a.length&&prefix<b.length&&a[prefix]==b[prefix]){prefix++;}
  var ae=a.length,be=b.length;while(ae>prefix&&be>prefix&&a[ae-1]==b[be-1]){ae--;be--;}
  if(ae==prefix&&be==prefix)return [];
  final n=ae-prefix,m=be-prefix;
  // Bound memory for very large documents. A coarse conflict is safer than an
  // approximate patch that silently loses text. Common prefix/suffix stay exact.
  if(n*m>2000000)return [_Edit(prefix,ae,next.sublist(prefix,be),mine)];
  final rows=List.generate(n+1,(_)=>Uint32List(m+1));
  for(var i=n-1;i>=0;i--){for(var j=m-1;j>=0;j--){rows[i][j]=a[prefix+i]==b[prefix+j]?rows[i+1][j+1]+1:(rows[i+1][j]>rows[i][j+1]?rows[i+1][j]:rows[i][j+1]);}}
  final result=<_Edit>[];var i=0,j=0;
  while(i<n||j<m){
    if(i<n&&j<m&&a[prefix+i]==b[prefix+j]){i++;j++;continue;}
    final start=i,replacement=<DocumentSegment>[];
    while(i<n||j<m){
      if(i<n&&j<m&&a[prefix+i]==b[prefix+j])break;
      if(j<m&&(i==n||rows[i][j+1]>rows[i+1][j])){replacement.add(next[prefix+j++]);}else{i++;}
    }
    result.add(_Edit(prefix+start,prefix+i,replacement,mine));
  }
  return result;
}
bool _overlap(_Edit a,_Edit b){
  if(a.start==a.end&&b.start==b.end)return a.start==b.start;
  if(a.start==a.end)return a.start>=b.start&&a.start<b.end;
  if(b.start==b.end)return b.start>=a.start&&b.start<a.end;
  return a.start<b.end&&b.start<a.end;
}
class DocumentMergePart {
  DocumentMergePart(this.original,this.mine,this.remote,this.firstLine,this.lastLine,this.conflict);
  final DocumentSegment original,mine,remote;
  final int firstLine,lastLine;final bool conflict;
}
class DocumentMergePlan {
  DocumentMergePlan(this.remoteNote,this.localNote,this.baseNote,this.parts);
  final Map<String,dynamic> remoteNote,localNote,baseNote;
  final List<DocumentMergePart> parts;
  bool get hasConflicts=>parts.any((p)=>p.conflict);
  Map<String,dynamic> resolve([Map<int,DocumentSegment> choices=const {}]){
    final joined=DocumentSegment.join([for(var i=0;i<parts.length;i++)choices[i]??parts[i].mine]);
    final result=jsonDecode(jsonEncode(remoteNote)) as Map<String,dynamic>;
    final project=result['project'] as Map;
    project['document']=joined.text;project['documentLinks']=joined.links.map((b)=>b.toJson()).toList();project['name']=documentTitle(joined.text);project['words']=[];
    final before=Set<dynamic>.from(baseNote['project']['tags']??[]),mine=Set<dynamic>.from(localNote['project']['tags']??[]),remote=Set<dynamic>.from(project['tags']??[]);
    project['tags']=(remote..removeAll(before.difference(mine))..addAll(mine.difference(before))).toList();
    result['content']=joined.text;
    return result;
  }
}
DocumentMergePlan mergeDocument(Map<String,dynamic> baseNote,Map<String,dynamic> localNote,Map<String,dynamic> remoteNote){
  final base=_lines(documentSegment(baseNote)),local=_lines(documentSegment(localNote)),remote=_lines(documentSegment(remoteNote));
  final edits=[..._edits(base,local,true),..._edits(base,remote,false)]..sort((a,b)=>a.start!=b.start?a.start.compareTo(b.start):a.end.compareTo(b.end));
  final parts=<DocumentMergePart>[];var cursor=0,line=1;
  void plain(List<DocumentSegment> chunks){final part=DocumentSegment.join(chunks);parts.add(DocumentMergePart(part,part,part,line,line+ '\n'.allMatches(part.text).length,false));line+='\n'.allMatches(part.text).length;}
  while(edits.isNotEmpty){
    final group=[edits.removeAt(0)];var grew=true;
    while(grew){grew=false;for(final e in List<_Edit>.of(edits)){if(group.any((g)=>_overlap(g,e))){group.add(e);edits.remove(e);grew=true;}}}
    final start=group.map((e)=>e.start).reduce((a,b)=>a<b?a:b),end=group.map((e)=>e.end).reduce((a,b)=>a>b?a:b);
    if(start>cursor)plain(base.sublist(cursor,start));
    DocumentSegment version(bool mine){
      final own=group.where((e)=>e.mine==mine).toList()..sort((a,b)=>a.start.compareTo(b.start));
      final result=<DocumentSegment>[];var at=start;
      for(final e in own){result.addAll(base.sublist(at,e.start));result.addAll(e.lines);at=e.end;}
      result.addAll(base.sublist(at,end));return DocumentSegment.join(result);
    }
    final original=DocumentSegment.join(base.sublist(start,end)),left=version(true),right=version(false);
    final both=group.any((e)=>e.mine)&&group.any((e)=>!e.mine);
    final selected=group.any((e)=>e.mine)?left:right;
    final count='\n'.allMatches(original.text).length;
    parts.add(DocumentMergePart(original,selected,right,line,line+(count>0?count-1:0),both&&left.signature!=right.signature));line+=count;cursor=end;
  }
  if(cursor<base.length)plain(base.sublist(cursor));
  return DocumentMergePlan(remoteNote,localNote,baseNote,parts);
}
class DocumentMergeConflict implements Exception {
  DocumentMergeConflict(this.plan,this.remoteItem);
  final DocumentMergePlan plan;
  final Map<String,dynamic> remoteItem;
  @override String toString()=>'같은 부분이 수정되었습니다. 충돌한 줄을 확인해주세요.';
}

import 'package:flutter/material.dart';
import '../sync/document_merge.dart';
import 'label_links.dart';
import 'document_line_numbers.dart';

Future<Map<String,dynamic>?> resolveDocumentConflict(BuildContext context,DocumentMergeConflict conflict)async{
  final choices=<int,DocumentSegment>{};
  for(var i=0;i<conflict.plan.parts.length;i++){
    final part=conflict.plan.parts[i];if(!part.conflict)continue;
    if(!context.mounted)return null;
    final result=await showDialog<DocumentSegment>(context:context,barrierDismissible:false,builder:(_)=>_ConflictDialog(part));
    if(result==null)return null;choices[i]=result;
  }
  return conflict.plan.resolve(choices);
}
class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog(this.part);
  final DocumentMergePart part;
  @override State<_ConflictDialog> createState()=>_ConflictDialogState();
}
class _ConflictDialogState extends State<_ConflictDialog>{
  late final controller=LabelTextController(widget.part.mine.text,widget.part.mine.links);
  final scroll=ScrollController();
  @override void dispose(){controller.dispose();scroll.dispose();super.dispose();}
  Widget source(String title,DocumentSegment value)=>ExpansionTile(initiallyExpanded:true,title:Text(title),children:[Padding(padding:const EdgeInsets.all(8),child:SelectableText(value.text.isEmpty?'(삭제됨)':value.text,style:const TextStyle(fontFamily:'monospace')))]);
  void use(DocumentSegment value){controller.loadDocument(value.text,value.links);}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text('문서 충돌 · 원본 ${widget.part.firstLine}–${widget.part.lastLine}줄'),content:SizedBox(width:720,height:MediaQuery.sizeOf(context).height*.65,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('같은 부분을 서로 다르게 수정했습니다. 아래 결과를 수정한 뒤 병합해주세요.'),
    Flexible(child:SingleChildScrollView(child:Column(children:[source('편집 시작 원본',widget.part.original),source('내 변경',widget.part.mine),source('서버 최신 변경',widget.part.remote)]))),
    Wrap(spacing:8,children:[TextButton(onPressed:()=>use(widget.part.mine),child:const Text('내 변경 사용')),TextButton(onPressed:()=>use(widget.part.remote),child:const Text('서버 변경 사용'))]),
    Expanded(child:DocumentLineNumbers(controller:controller,scroll:scroll,child:TextField(key:const ValueKey('document-merge-input'),controller:controller,scrollController:scroll,expands:true,minLines:null,maxLines:null,textAlignVertical:TextAlignVertical.top,decoration:const InputDecoration(labelText:'병합 결과',alignLabelWithHint:true,border:OutlineInputBorder())))),
  ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소')),FilledButton(onPressed:()=>Navigator.pop(context,DocumentSegment(controller.text,List.of(controller.bindings))),child:const Text('병합 적용'))]);
}

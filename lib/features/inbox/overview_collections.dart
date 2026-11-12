import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../capture/media_storage.dart';
import '../capture/capture_models.dart';
import 'desktop_menu_frame.dart';
import 'element_store.dart';
import 'project_page.dart';
import 'thought_filters.dart';
import 'thought_settings.dart';
import 'workspace_storage.dart';
import 'workspace_routes.dart';

String overviewTime(DateTime value) {
 final d=value.toLocal();String two(int n)=>n.toString().padLeft(2,'0');
 return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
String overviewAuthor(WorkspaceStorage? storage,String kind,String id)=>storage?.itemMetadata?.call(kind,id)?['author'] as String? ?? (storage?.owner?.startsWith('guest-')==true?'비회원':'작성자 정보 없음');
String excerpt(String text)=>text.replaceAll(RegExp(r'[=*_`<>]'),'').replaceAll(RegExp(r'\s+'),' ').trim();
class DocumentCollection extends StatefulWidget {
 const DocumentCollection({super.key,required this.notes,required this.selector,this.storage,this.onOpen});
 final List<Note> notes;final Widget selector;final WorkspaceStorage? storage;final Future<void> Function(Note)? onOpen;
 @override State<DocumentCollection> createState()=>_DocumentCollectionState();
}
class _DocumentCollectionState extends State<DocumentCollection>{
 String query='';
 DateTime? updated(Note n){final server=DateTime.tryParse(widget.storage?.itemMetadata?.call('list:notes',n.id)?['updatedAt'] as String? ?? '');return server!=null && (n.updatedAt==null || server.isAfter(n.updatedAt!))?server:n.updatedAt;}
 DateTime modified(Note n)=>updated(n)??n.createdAt;
 @override Widget build(BuildContext context){final notes=widget.notes.where((n)=>n.project!=null && '${n.project!.title}\n${n.project!.content}'.toLowerCase().contains(query.toLowerCase())).toList()..sort((a,b)=>modified(b).compareTo(modified(a)));
 return Scaffold(appBar:AppBar(title:const WorkspaceTitle('전체 보기'),actions:const [DesktopMenuAction()]),body:DesktopMenuBody(child:Column(children:[widget.selector,
 Padding(padding:const EdgeInsets.all(12),child:TextField(key:const ValueKey('documents-search'),onChanged:(value)=>setState(()=>query=value.trim()),decoration:const InputDecoration(hintText:'문서 제목·내용 찾기',prefixIcon:Icon(Icons.search),isDense:true))),
 Expanded(child:notes.isEmpty?const Center(child:Text('일치하는 문서가 없습니다.')):ListView.separated(padding:const EdgeInsets.symmetric(horizontal:12),itemCount:notes.length,separatorBuilder:(_,index)=>const Divider(height:1),itemBuilder:(context,index){final n=notes[index],p=n.project!;return ListTile(key:ValueKey('document-${p.id}'),contentPadding:const EdgeInsets.symmetric(horizontal:8,vertical:8),title:Text(p.title,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const SizedBox(height:5),Text(excerpt(p.content),maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:8),Text('${updated(n)==null?'작성 ${overviewTime(n.createdAt)} · 수정 기록 없음':'수정 ${overviewTime(modified(n))}'} · ${overviewAuthor(widget.storage,'list:notes',n.id)}',style:Theme.of(context).textTheme.labelSmall)]),onTap:()async{if(widget.onOpen!=null){await widget.onOpen!(n);}else{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProjectPage(project:p)));}if(mounted)setState((){});});})),
 ])));
 }
}
class AttachmentCollection extends StatefulWidget {
 const AttachmentCollection({super.key,required this.audio,required this.selector,required this.filters,this.storage,this.onChanged});
 final bool audio;final Widget selector;final ThoughtFilterSelection filters;final WorkspaceStorage? storage;final VoidCallback? onChanged;
 @override State<AttachmentCollection> createState()=>_AttachmentCollectionState();
}
class _AttachmentCollectionState extends State<AttachmentCollection>{
 bool details=false;
 void refresh(){if(mounted)setState((){});}
 @override void initState(){super.initState();elements.addListener(refresh);widget.filters.addListener(refresh);}
 @override void dispose(){elements.removeListener(refresh);widget.filters.removeListener(refresh);super.dispose();}
 String duration(int ms){final seconds=(ms/1000).ceil();return '${seconds~/60}:${(seconds%60).toString().padLeft(2,'0')}';}
 @override Widget build(BuildContext context){
 final entries=<({ElementRecord record,String id,PhotoAttachment? photo,VoiceAttachment? voice})>[];
 for(final r in elements.records.values.where((r)=>canBrowseThought(r)&&widget.filters.matches(r))){if(widget.audio){for(final v in r.recordings){entries.add((record:r,id:v.id,photo:null,voice:v));}}else{for(final p in r.photos){entries.add((record:r,id:p.id,photo:p,voice:null));}}}
 entries.sort((a,b)=>b.record.createdAt.compareTo(a.record.createdAt));
 Widget tile(int index){final e=entries[index],r=e.record;final preview=e.voice!=null?Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(duration(e.voice!.durationMs),style:Theme.of(context).textTheme.titleMedium),const Icon(Icons.graphic_eq,size:48)]):StoredThumbnail(key:ValueKey(e.id),id:e.id,owner:widget.storage?.owner,name:e.photo!.name);
 return Card(clipBehavior:Clip.antiAlias,child:InkWell(key:ValueKey('attachment-${e.id}'),onTap:()async{await showElementMetadata(context,r.text);widget.onChanged?.call();if(mounted)setState((){});},child:details?Padding(padding:const EdgeInsets.all(12),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:96,height:96,child:preview),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r.text,maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:8),Text('${overviewTime(r.createdAt)} · ${overviewAuthor(widget.storage,'list:elements',r.id)}',style:Theme.of(context).textTheme.labelSmall),Row(children:[if(widget.audio?r.photos.isNotEmpty:r.recordings.isNotEmpty)Tooltip(message:widget.audio?'사진 있음':'음성 있음',child:Icon(widget.audio?Icons.image_outlined:Icons.volume_up_outlined,size:18)),if(r.location!=null)const Padding(padding:EdgeInsets.only(left:6),child:Tooltip(message:'위치 기록 있음',child:Icon(Icons.place_outlined,size:18)))])]))])):preview));
 }
 return Scaffold(appBar:AppBar(title:const WorkspaceTitle('전체 보기'),actions:[PopupMenuButton<bool>(tooltip:'정렬',icon:const Icon(Icons.sort),onSelected:(value)=>setState(()=>details=value),itemBuilder:(_)=>[CheckedPopupMenuItem(value:false,checked:!details,child:const Text('격자보기')),CheckedPopupMenuItem(value:true,checked:details,child:const Text('자세히'))]),const DesktopMenuAction()]),body:DesktopMenuBody(child:Column(children:[widget.selector,Expanded(child:entries.isEmpty?Center(child:Text(widget.audio?'추가한 음성이 없습니다.':'추가한 사진이 없습니다.')):details?ListView.builder(padding:const EdgeInsets.all(12),itemCount:entries.length,itemBuilder:(_,i)=>tile(i)):GridView.builder(padding:const EdgeInsets.all(12),gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:200,mainAxisSpacing:8,crossAxisSpacing:8),itemCount:entries.length,itemBuilder:(_,i)=>tile(i)))])));
 }
}
class StoredThumbnail extends StatefulWidget {
 const StoredThumbnail({super.key,required this.id,required this.owner,required this.name});
 final String id,name;final String? owner;
 @override State<StoredThumbnail> createState()=>_StoredThumbnailState();
}
class _StoredThumbnailState extends State<StoredThumbnail>{
 late final Future<Uint8List?> bytes=MediaStorage.read(widget.id,owner:widget.owner);
 @override Widget build(BuildContext context)=>FutureBuilder<Uint8List?>(future:bytes,builder:(context,snapshot){if(snapshot.data==null)return Center(child:snapshot.connectionState==ConnectionState.waiting?const SizedBox.square(dimension:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.broken_image_outlined));return Image.memory(snapshot.data!,fit:BoxFit.cover,cacheWidth:400,semanticLabel:widget.name,errorBuilder:(_,error,stack)=>const Icon(Icons.broken_image_outlined));});
}

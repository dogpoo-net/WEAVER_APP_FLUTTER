import '../sync/document_merge.dart';
import 'workspace_storage.dart';
import 'document_markup.dart';
import 'workspace_routes.dart';
import 'element_binding.dart';
import 'dart:math';
import 'desktop_menu_frame.dart';
import 'paragraph_editor.dart';
import 'package:flutter/material.dart';
import 'deferred_screen.dart';
import 'project_document_editor.dart' deferred as document_editor;

class WritingProject {
  WritingProject(
    this.paragraphs,
    List<String> words, {
    required this.name,
    this.folder, String? id,
  }) : id = id ?? 'project-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}', words = List.of(words);
  final String id;
  List<ElementBinding> documentLinks = [];
  String? document;
  final Set<String> tags = {};
  String get content => document ?? paragraphs.map((p) => p.text).join('\n\n');
  String name;
  String? folder;
  List<Paragraph> paragraphs;
  final List<String> words;
  String get title => document == null ? name : documentTitle(document!);
}

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.project, this.onChanged, this.onSave, this.onHistory, this.onLease, this.storage, this.onReload, this.onOpenRefresh, this.openEditor = false, this.projects = const []});
  final bool openEditor;
  final Future<Map<String,dynamic>> Function(String,String,bool)? onLease;
  final WorkspaceStorage? storage;
  final Future<void> Function()? onReload, onOpenRefresh;
  final WritingProject project;
  final List<WritingProject> projects;
  final Future<void> Function()? onChanged, onSave;
  final Future<void> Function(String)? onHistory;
  @override State<ProjectPage> createState()=>_ProjectPageState();
}
class _ProjectPageState extends State<ProjectPage>{

 String _revisionLabel = '';
 int _revisionRequest = 0;
 Future<void> _refreshRevision() async {
   final request = ++_revisionRequest;
   final id = widget.project.id;
   final label = await documentRevisionLabel(widget.storage, id);
   if (!mounted || request != _revisionRequest) return;
   setState(() => _revisionLabel = label);

 }

 bool _editing = false, _deleted = false;
 Future<void> _editDocument() async {
   if (_editing) return;
   _editing = true;
   try {
     if (!await loadScreen(context, document_editor.loadLibrary) || !mounted) return;
     if (_deleted || ModalRoute.of(context)?.isCurrent == false) return;
     await Navigator.push(context, MaterialPageRoute<void>(
       builder: (_) => DesktopMenuFrame(child: document_editor.ProjectDocumentEditor(
         project: widget.project,
         projects: widget.projects,
         onChanged: widget.onChanged,
         onSave: widget.onSave,
         onHistory: widget.onHistory,
         onLease: widget.onLease,
         storage: widget.storage,
         onReload: widget.onReload,
       )),
     ));
   } finally {
     _editing = false;
     if (mounted) { _changed(); _refreshRevision(); }
   }
 }

 void _changed(){
   if(!mounted || _editing)return;
   final raw=widget.storage?.read();
   if(raw!=null){
     final next=WorkspaceSnapshot.decode(raw).notes.where((n)=>n.project?.id==widget.project.id).firstOrNull?.project;
     _deleted=next==null;
     if(next!=null){final p=widget.project;p.document=next.document;p.documentLinks=next.documentLinks;p.name=next.name;p.paragraphs=next.paragraphs;p.tags..clear()..addAll(next.tags);}
   }
   setState((){});
 }
 @override
 void initState() {
   super.initState();
   _refreshRevision();
   widget.storage?.documentDraftChanges.addListener(_changed);
   if (widget.openEditor) {
     afterWorkspaceRouteEntrance(context, _editDocument);
     return;
   }
   final refresh = widget.onOpenRefresh;
   if (refresh != null) {
     afterWorkspaceRouteEntrance(context, () async {
       try {
         await refresh();
         if (mounted) { _changed(); _refreshRevision(); }
       } catch (_) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('서버 변경을 확인하지 못했습니다. 기기의 문서를 표시합니다.')),
         );
       }
     });
   }
 }
 @override void dispose(){widget.storage?.documentDraftChanges.removeListener(_changed);super.dispose();}
 Map<String,dynamic>? get _draft=>widget.storage?.documentDraft(widget.project.id);
 DocumentSegment get _display=>_draft==null?DocumentSegment(widget.project.content,widget.project.documentLinks):DocumentSegment(_draft!['text'] as String,[for(final b in _draft!['links'] as List)ElementBinding(b['id'] as String,b['start'] as int,b['end'] as int)]);
 @override Widget build(BuildContext context)=>DesktopMenuFrame(child:Scaffold(appBar:AppBar(title:WorkspaceTitle(widget.project.title),actions:[if(widget.onHistory!=null)IconButton(tooltip:'문서 변경 이력',onPressed:()=>widget.onHistory!(widget.project.id),icon:const Icon(Icons.history)),if(!_deleted)IconButton(tooltip:'문서 수정',icon:const Icon(Icons.edit_outlined),onPressed: _editDocument)]),body:DesktopMenuBody(child:_deleted ? const Center(child: Text('다른 기기에서 삭제된 문서입니다.')) : documentReadingView(context, _display, _revisionLabel, _draft != null))));
}

Future<String> documentRevisionLabel(WorkspaceStorage? storage, String id) async {
   final note = storage?.read();
   final local = note == null ? null : WorkspaceSnapshot.decode(note).notes
       .where((n) => n.project?.id == id).firstOrNull;
   DateTime? time = local?.updatedAt;
   String author = '알 수 없음';
   try {
     final revision = await storage?.latestDocumentRevision?.call(id);
     if (revision != null) {
       time = DateTime.tryParse(revision['createdAt'].toString()) ?? time;
       author = revision['actorName']?.toString() ?? author;
     }
   } catch (_) { /* The local timestamp is also available offline. */ }
   final stamp = time?.toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ') ?? '수정 시각 미상';
   return "$stamp  작성자: $author";
}

Widget documentReadingView(BuildContext context, DocumentSegment document, String revisionLabel, bool dirty) =>
SelectionArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[if(dirty)const Padding(padding:EdgeInsets.only(bottom:12),child:Text('아직 저장되지 않았습니다.',style:TextStyle(color:Colors.red))),if (revisionLabel.isNotEmpty) Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(revisionLabel, textAlign: TextAlign.right,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
Container(padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    borderRadius: BorderRadius.circular(8)),
  child: DocumentMarkup(text:document.text,links:document.links))])))));

import 'workspace_storage.dart';
import 'document_markup.dart';
import 'workspace_routes.dart';
import 'element_binding.dart';
import 'dart:math';
import 'desktop_menu_frame.dart';
import 'paragraph_editor.dart';
import 'package:flutter/material.dart';
import 'project_document_editor.dart';

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
  const ProjectPage({super.key, required this.project, this.onChanged, this.onSave, this.onHistory, this.onLease, this.storage, this.onReload, this.projects = const []});
  final Future<Map<String,dynamic>> Function(String,String,bool)? onLease;
  final WorkspaceStorage? storage;
  final Future<void> Function()? onReload;
  final WritingProject project;
  final List<WritingProject> projects;
  final Future<void> Function()? onChanged, onSave;
  final Future<void> Function(String)? onHistory;
  @override State<ProjectPage> createState()=>_ProjectPageState();
}
class _ProjectPageState extends State<ProjectPage>{
 void _changed(){if(mounted)setState((){});}
 @override void initState(){super.initState();widget.storage?.liveChanges.addListener(_changed);}
 @override void dispose(){widget.storage?.liveChanges.removeListener(_changed);super.dispose();}
 @override Widget build(BuildContext context)=>DesktopMenuFrame(child:Scaffold(appBar:AppBar(title:WorkspaceTitle(widget.project.title),actions:[if(widget.onHistory!=null)IconButton(tooltip:'문서 변경 이력',onPressed:()=>widget.onHistory!(widget.project.id),icon:const Icon(Icons.history)),IconButton(tooltip:'문서 수정',icon:const Icon(Icons.edit_outlined),onPressed:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>DesktopMenuFrame(child:ProjectDocumentEditor(project:widget.project,projects:widget.projects,onChanged:widget.onChanged,onSave:widget.onSave,onHistory:widget.onHistory,onLease:widget.onLease,storage:widget.storage,onReload:widget.onReload))));if(mounted)setState((){});})]),body:DesktopMenuBody(child:SelectionArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),child:DocumentMarkup(text:widget.project.content,links:widget.project.documentLinks))))))));
}

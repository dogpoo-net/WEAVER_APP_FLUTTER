import 'element_binding.dart';
import 'document_syntax.dart';
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

class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key, required this.project, this.onChanged, this.onSave, this.projects = const []});
  final WritingProject project;
  final List<WritingProject> projects;
  final Future<void> Function()? onChanged, onSave;
  @override
  Widget build(BuildContext context) => DesktopMenuFrame(child: ProjectDocumentEditor(project: project, projects: projects, onChanged: onChanged, onSave: onSave));
}

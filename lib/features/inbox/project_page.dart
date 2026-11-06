import 'desktop_menu_frame.dart';
import 'paragraph_editor.dart';
import 'package:flutter/material.dart';
import 'project_document_editor.dart';

class WritingProject {
  WritingProject(
    this.paragraphs,
    List<String> words, {
    required this.name,
    this.folder,
  }) : words = List.of(words);
  String? document;
  final Set<String> tags = {};
  String get content => document ?? paragraphs.map((p) => p.text).join('\n\n');
  String name;
  String? folder;
  List<Paragraph> paragraphs;
  final List<String> words;
  String get title => name;
}

class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key, required this.project, this.onChanged, this.initialParagraph, this.initialOffset, this.available = const []});
  final WritingProject project;
  final Future<void> Function()? onChanged;
  final int? initialParagraph, initialOffset;
  final List<Paragraph> available;
  @override
  Widget build(BuildContext context) => DesktopMenuFrame(child: ProjectDocumentEditor(project: project, onChanged: onChanged));
}

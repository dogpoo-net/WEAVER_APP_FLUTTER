import 'desktop_menu_frame.dart';
import 'package:flutter/material.dart';
import 'paragraph_editor.dart';
import 'project_document_editor.dart';

class ProjectBuilder extends StatelessWidget {
  const ProjectBuilder({super.key, required this.available, required this.words});
  final List<Paragraph> available;
  final List<String> words;
  @override
  Widget build(BuildContext context) => const DesktopMenuFrame(child: ProjectDocumentEditor());
}

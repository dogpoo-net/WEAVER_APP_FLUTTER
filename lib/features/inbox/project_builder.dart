import 'package:flutter/material.dart';
import 'paragraph_editor.dart';

class ProjectBuilder extends StatelessWidget {
  const ProjectBuilder({super.key, required this.available, required this.words});
  final List<Paragraph> available;
  final List<String> words;
  @override
  Widget build(BuildContext context) => ParagraphEditor(
    projectEditing: true, projectCreation: true, available: available, words: words,
  );
}

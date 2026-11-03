import 'project_folders.dart';

import 'package:flutter/material.dart';

import 'paragraph_editor.dart';
import 'word_badge.dart';
import 'element_store.dart';
import 'hashtags.dart';

class WritingProject {
  WritingProject(
    this.paragraphs,
    List<String> words, {
    required this.name,
    this.folder,
  }) : words = List.of(words);
  String name;
  String? folder;
  List<Paragraph> paragraphs;
  final List<String> words;
  String get title => name;
}

class ProjectPage extends StatefulWidget {
  const ProjectPage({
    super.key,
    required this.project,
    this.onChanged,
    this.initialParagraph,
    this.initialOffset,
  });
  final int? initialParagraph;
  final int? initialOffset;
  final Future<void> Function()? onChanged;
  final WritingProject project;
  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  int _tab = 0;
  final _word = TextEditingController();
  @override
  void initState() {
    super.initState();
    elements.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _move() async {
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('프로젝트 폴더'),
        children: [
          for (final name in ['', ...projectFolders])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name.isEmpty ? '미분류' : name),
            ),
        ],
      ),
    );
    if (folder == null || !mounted) return;
    setState(() => widget.project.folder = folder.isEmpty ? null : folder);
    await widget.onChanged?.call();
  }

  @override
  void dispose() {
    elements.removeListener(_refresh);
    _word.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final result = await Navigator.push<List<Paragraph>>(
      context,
      MaterialPageRoute(
        builder: (_) => ParagraphEditor(
          projectEditing: true,
          initial: widget.project.paragraphs,
          words: elements.words,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => widget.project.paragraphs = result);
      await widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    elements.indexProject(project);
    final usedWords = project.paragraphs
        .expand((p) => elements.matches(p.text).map((h) => h.word))
        .toSet();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          project.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _move,
            tooltip: '폴더 이동',
            icon: const Icon(Icons.drive_file_move_outline),
          ),
          IconButton(
            onPressed: _edit,
            tooltip: '프로젝트 편집',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in ['미리보기', '원소', '문단'].asMap().entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _tab == entry.key,
                          onSelected: (_) => setState(() => _tab = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_tab == 0) ...[
                    const Text('미리보기', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 20),
                    for (final entry in project.paragraphs.asMap().entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: ElementText(
                          entry.value.text,
                          focusOffset: widget.initialParagraph == entry.key
                              ? widget.initialOffset
                              : null,
                          style: TextStyle(
                            height: 1.7,
                            fontSize: entry.value.role == ParagraphRole.title
                                ? 30
                                : entry.value.role == ParagraphRole.subtitle
                                ? 22
                                : 16,
                            fontWeight: entry.value.role == ParagraphRole.body
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                  if (_tab == 1) ...[
                    const Text('이 프로젝트에서 사용한 원소'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: usedWords
                          .map(
                            (w) => WordBadge(
                              word: w,
                              onTap: () {
                                showElementMetadata(context, w);
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _word,
                      decoration: const InputDecoration(
                        labelText: '원소단어 추가',
                        hintText: '원소 내용 #태그',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        final word = _word.text.trim();
                        if (parseTaggedInput(word).text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('태그와 함께 원소 내용을 입력해주세요.'),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          elements.add(word);
                          _word.clear();
                          widget.onChanged?.call();
                        });
                      },
                      child: const Text('글로벌 원소 저장'),
                    ),
                  ],
                  if (_tab == 2) ...[
                    for (var i = 0; i < project.paragraphs.length; i++)
                      Card(
                        child: ListTile(
                          title: Text(project.paragraphs[i].text),
                          subtitle: Text(
                            '문단 ${i + 1} · ${['제목', '부제', '본문'][project.paragraphs[i].role.index]}',
                          ),
                          onTap: _edit,
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    '저장한 프로젝트는 이 기기에 보관됩니다.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

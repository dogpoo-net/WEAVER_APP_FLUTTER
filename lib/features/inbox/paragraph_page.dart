import 'package:flutter/material.dart';
import 'workspace_storage.dart';
import 'word_badge.dart';
import 'element_store.dart';

class ParagraphPage extends StatefulWidget {
  const ParagraphPage({super.key, required this.note, required this.onEdit,
    required this.onDelete, required this.onTag});
  final Note note;
  final Future<void> Function() onEdit, onDelete;
  final Future<void> Function(String) onTag;
  @override
  State<ParagraphPage> createState() => _ParagraphPageState();
}

class _ParagraphPageState extends State<ParagraphPage> {
  Future<void> _delete() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('저장된 문단을 삭제할까요?'),
      content: const Text('프로젝트에 불러온 문장은 그대로 유지됩니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
      ],
    ));
    if (yes != true || !mounted) return;
    await widget.onDelete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final used = elements.matches(note.content).map((hit) => hit.word).toSet();
    final date = note.createdAt.toLocal();
    return Scaffold(
      appBar: AppBar(title: const Text('문단'), actions: [
        IconButton(tooltip: '문단 수정', icon: const Icon(Icons.edit_outlined), onPressed: () async {
          await widget.onEdit();
          if (mounted) setState(() {});
        }),
        IconButton(tooltip: '문단 삭제', icon: const Icon(Icons.delete_outline), onPressed: _delete),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          ElementText(note.content, style: const TextStyle(fontSize: 16, height: 1.7)),
          const Divider(height: 40),
          Text('작성일 · ${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
          const SizedBox(height: 16),
          const Text('태그'),
          if (note.tags.isEmpty) const Text('태그가 없어요'),
          Wrap(spacing: 6, children: [for (final tag in note.tags)
            ActionChip(label: Text('#$tag'), onPressed: () => widget.onTag(tag))]),
          const SizedBox(height: 16),
          const Text('사용한 원소'),
          if (used.isEmpty) const Text('사용한 원소가 없어요'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final word in used)
            WordBadge(word: word, onTap: () => showElementMetadata(context, word))]),
        ]),
      ))),
    );
  }
}

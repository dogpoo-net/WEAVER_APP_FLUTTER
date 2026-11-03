import 'package:flutter/material.dart';

import 'paragraph_editor.dart';
import 'project_page.dart';

class ProjectBuilder extends StatefulWidget {
  const ProjectBuilder({
    super.key,
    required this.available,
    required this.words,
  });
  final List<Paragraph> available;
  final List<String> words;
  @override
  State<ProjectBuilder> createState() => _ProjectBuilderState();
}

class _ProjectBuilderState extends State<ProjectBuilder> {
  final _name = TextEditingController();
  final List<int> _selected = [];
  bool _customName = false;
  ParagraphRole _filter = ParagraphRole.title;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(int index) {
    setState(() {
      final p = widget.available[index];
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        if (p.role == ParagraphRole.title &&
            _selected.any(
              (i) => widget.available[i].role == ParagraphRole.title,
            )) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('제목은 하나만 선택할 수 있어요. 기존 제목을 해제해주세요.')),
          );
          return;
        }
        _selected.add(index);
      }
      if (!_customName) {
        final titles = _selected.where(
          (i) => widget.available[i].role == ParagraphRole.title,
        );
        _name.text = titles.isEmpty
            ? ''
            : widget.available[titles.first].text.split('\n').first;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('프로젝트 생성')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const ValueKey('project-name'),
                controller: _name,
                onChanged: (_) => setState(() => _customName = true),
                decoration: const InputDecoration(
                  labelText: '프로젝트 이름',
                  helperText: '제목을 고르면 자동 입력됩니다. 직접 바꿀 수도 있어요.',
                ),
              ),
              const SizedBox(height: 20),
              const Text('선택한 순서대로 글이 이어집니다. 제목은 하나만 선택할 수 있어요.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ParagraphRole.values
                    .map(
                      (role) => ChoiceChip(
                        label: Text(['제목', '부제', '본문'][role.index]),
                        selected: role == _filter,
                        onSelected: (_) => setState(() => _filter = role),
                      ),
                    )
                    .toList(),
              ),
              for (final entry in widget.available.asMap().entries.where(
                (e) => e.value.role == _filter,
              ))
                CheckboxListTile(
                  key: ValueKey('pick-${entry.key}'),
                  title: Text(entry.value.text),
                  value: _selected.contains(entry.key),
                  onChanged: (_) => _toggle(entry.key),
                ),
              if (!widget.available.any((p) => p.role == _filter))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('이 유형의 문단이 없어요. 먼저 문단 쓰기에서 만들어주세요.'),
                ),
              const Divider(height: 32),
              const Text('선택 순서'),
              for (var order = 0; order < _selected.length; order++)
                ListTile(
                  leading: Text('${order + 1}'),
                  title: Text(widget.available[_selected[order]].text),
                  trailing: IconButton(
                    tooltip: '선택 해제',
                    icon: const Icon(Icons.close),
                    onPressed: () => _toggle(_selected[order]),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selected.isEmpty || _name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        WritingProject(
                          _selected.map((i) => widget.available[i]).toList(),
                          widget.words,
                          name: _name.text.trim(),
                        ),
                      ),
                child: const Text('프로젝트 만들기'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String?> showDocumentFootnotes(
  BuildContext context, {
  required Map<String, String> notes,
  required String Function(String text) onAdd,
}) => showDialog<String>(
  context: context,
  builder: (context) => _DocumentFootnotes(notes: notes, onAdd: onAdd),
);

class _DocumentFootnotes extends StatefulWidget {
  const _DocumentFootnotes({required this.notes, required this.onAdd});

  final Map<String, String> notes;
  final String Function(String text) onAdd;

  @override
  State<_DocumentFootnotes> createState() => _DocumentFootnotesState();
}

class _DocumentFootnotesState extends State<_DocumentFootnotes> {
  late final _notes = Map<String, String>.of(widget.notes);

  bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

  EdgeInsets _insets(BuildContext context) => EdgeInsets.symmetric(
    horizontal: _compact(context) ? 8 : 40,
    vertical: 16,
  );

  EdgeInsets _contentPadding(BuildContext context) => EdgeInsets.fromLTRB(
    _compact(context) ? 16 : 24,
    16,
    _compact(context) ? 16 : 24,
    12,
  );

  Future<void> _add() async {
    var draft = '';
    void submit(BuildContext context, String text) {
      final value = text.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
      if (value.isNotEmpty) Navigator.pop(context, value);
    }

    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('각주 추가'),
        insetPadding: _insets(context),
        contentPadding: _contentPadding(context),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: TextField(
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.deny(
                RegExp(r'[\r\n]+'),
                replacementString: ' ',
              ),
            ],
            onSubmitted: (value) => submit(context, value),
            decoration: const InputDecoration(
              labelText: '각주 내용',
              alignLabelWithHint: true,
            ),
            onChanged: (value) => draft = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => submit(context, draft),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (!mounted || input == null) return;
    final id = widget.onAdd(input);
    setState(() => _notes[id] = input);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: _insets(context),
    contentPadding: _contentPadding(context),
    title: Row(
      children: [
        const Expanded(child: Text('각주 관리')),
        IconButton(
          tooltip: '각주 추가',
          icon: const Icon(Icons.add),
          onPressed: _add,
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      height: _notes.isEmpty ? null : 300,
      child: _notes.isEmpty
          ? const Text('아직 각주가 없습니다.')
          : ListView.separated(
              shrinkWrap: true,
              itemCount: _notes.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final entry = _notes.entries.elementAt(index);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  trailing: TextButton(
                    onPressed: () => Navigator.pop(context, entry.key),
                    child: const Text('삽입'),
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}

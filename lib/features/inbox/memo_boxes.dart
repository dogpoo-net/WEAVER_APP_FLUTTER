import 'package:flutter/material.dart';
import 'element_store.dart';
import 'tag_colors.dart';

class MemoBox {
  MemoBox(this.name, {this.color = 0xFF90A4AE, this.folder, Iterable<String> ids = const []}) : elementIds = {...ids};
  final String name;
  int color;
  String? folder;
  final Set<String> elementIds;
}
final memoBoxes = <MemoBox>[];
final memoBoxFolders = <String>[];
class MemoDrag {
  const MemoDrag(this.id);
  final String id;
}

Future<MemoBox?> createMemoBox(BuildContext context) async {
  var draft = '';
  final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
    title: const Text('메모상자 만들기'),
    content: TextField(autofocus: true, maxLength: 60, onChanged: (value) => draft = value,
      decoration: const InputDecoration(labelText: '상자 이름'),
      onSubmitted: (value) { if (value.trim().isNotEmpty) Navigator.pop(context, value.trim()); }),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      TextButton(onPressed: () { if (draft.trim().isNotEmpty) Navigator.pop(context, draft.trim()); }, child: const Text('만들기'))],
  ));
  if (name == null) return null;
  final existing = memoBoxes.where((box) => box.name == name);
  if (existing.isNotEmpty) return existing.first;
  final box = MemoBox(name);
  memoBoxes.add(box);
  return box;
}

class MemoBoxTarget extends StatelessWidget {
  const MemoBoxTarget({super.key, required this.box, required this.onChanged, required this.child});
  final MemoBox box;
  final VoidCallback onChanged;
  final Widget child;
  @override
  Widget build(BuildContext context) => DragTarget<MemoDrag>(
    onWillAcceptWithDetails: (details) => !box.elementIds.contains(details.data.id),
    onAcceptWithDetails: (details) { box.elementIds.add(details.data.id); onChanged(); },
    builder: (context, candidates, rejected) => Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        color: candidates.isEmpty ? null : Color(box.color).withValues(alpha: .25)), child: child));
}

class MemoBoxPage extends StatefulWidget {
  const MemoBoxPage({super.key, required this.box, required this.onChanged});
  final MemoBox box;
  final VoidCallback onChanged;
  @override
  State<MemoBoxPage> createState() => _MemoBoxPageState();
}
class _MemoBoxPageState extends State<MemoBoxPage> {
  void _changed() { setState(() {}); widget.onChanged(); }
  Future<void> _add() async {
    final selected = {...widget.box.elementIds};
    var query = '';
    final result = await showDialog<Set<String>>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: const Text('메모 담기'),
        content: SizedBox(width: 420, height: 360, child: Column(children: [
          TextField(decoration: const InputDecoration(hintText: '메모에서 찾기', prefixIcon: Icon(Icons.search)),
            onChanged: (value) => update(() => query = value)),
          Expanded(child: ListView(children: [for (final record in elements.records.values)
            if (record.text.toLowerCase().contains(query.toLowerCase())) CheckboxListTile(
              title: Text(record.text, maxLines: 2, overflow: TextOverflow.ellipsis), value: selected.contains(record.id),
              onChanged: (checked) => update(() { if (checked == true) { selected.add(record.id); } else { selected.remove(record.id); } })),
          ])),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('담기'))],
      )));
    if (!mounted || result == null) return;
    widget.box.elementIds..clear()..addAll(result);
    _changed();
  }
  @override
  Widget build(BuildContext context) {
    final records = elements.records.values.where((record) => widget.box.elementIds.contains(record.id)).toList();
    return Scaffold(appBar: AppBar(title: Text(widget.box.name), actions: [
      IconButton(tooltip: '상자 색상 변경', icon: Icon(Icons.circle, color: Color(widget.box.color), size: 18),
        onPressed: () async {
          final color = await pickHashtagColor(context, widget.box.name, Color(widget.box.color), prefix: '');
          if (!mounted || color == null) return;
          widget.box.color = color.toARGB32(); _changed();
        }),
      IconButton(tooltip: '메모 추가', onPressed: _add, icon: const Icon(Icons.add)),
    ]), body: records.isEmpty ? const Center(child: Text('추가 버튼으로 메모를 담아보세요.')) : ListView(
      padding: const EdgeInsets.all(16), children: [for (final record in records) ListTile(
        title: Text(record.text, maxLines: 3, overflow: TextOverflow.ellipsis),
        onTap: () async { showElementMetadata(context, record.text); if (mounted) _changed(); },
        trailing: IconButton(tooltip: '상자에서 빼기', icon: const Icon(Icons.remove_circle_outline),
          onPressed: () { widget.box.elementIds.remove(record.id); _changed(); }),
      )]));
  }
}

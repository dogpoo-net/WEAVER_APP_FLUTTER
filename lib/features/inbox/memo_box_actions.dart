import 'package:flutter/material.dart';
import 'memo_boxes.dart';
import 'thought_filters.dart';

class MemoBoxActions extends StatelessWidget {
  const MemoBoxActions({super.key, required this.filters, required this.onCreate, this.onDelete});
  final ThoughtFilterSelection filters;
  final VoidCallback onCreate;
  final Future<void> Function(Set<String>)? onDelete;
  Future<void> remove(BuildContext context) async {
    final candidates = (filters.boxes.isEmpty ? memoBoxes : filters.boxes).where((b) => !b.isUnclassified).toList();
    final selected = filters.boxes.where((b) => !b.isUnclassified).map((b) => b.name).toSet();
    final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('메모상자 삭제'),
      content: SizedBox(width: 360, child: candidates.isEmpty ? const Text('삭제할 메모상자가 없습니다. 미분류 상자는 삭제할 수 없습니다.') : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final b in candidates) CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(b.name), value: selected.contains(b.name), onChanged: (value) => update(() { if (value == true) { selected.add(b.name); } else { selected.remove(b.name); } })),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')), TextButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('삭제'))],
    )));
    if (accepted != true || !context.mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('정말 삭제하시겠습니까?'),
      content: Text('${selected.join(', ')}\n\n포함된 메모는 전부 사라지고 되돌릴 수 없어요.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')), TextButton(style: TextButton.styleFrom(foregroundColor: const Color(0xFFD64550)), onPressed: () => Navigator.pop(context, true), child: const Text('삭제'))],
    ));
    if (confirmed != true || !context.mounted) return;
    try {
      await onDelete?.call(selected);
      filters.boxes.removeWhere((b) => selected.contains(b.name)); filters.toggle(null, null);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메모상자를 삭제했습니다.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 동기화를 완료하지 못했습니다. 다시 시도해주세요. $e')));
    }
  }
  @override Widget build(BuildContext context) => PopupMenuButton<String>(tooltip: '메모상자 관리', icon: const Icon(Icons.add), onSelected: (action) { if (action == 'create') { onCreate(); } else { remove(context); } }, itemBuilder: (_) => [
    const PopupMenuItem(value: 'create', child: Text('메모상자 만들기')),
    PopupMenuItem(value: 'delete', enabled: onDelete != null, child: const Text('메모상자 삭제')),
  ]);
}

import 'package:flutter/material.dart';
import 'graph_layout.dart';

class MemoBox {
  MemoBox(this.name, {this.color = 0xFF90A4AE, this.folder, Iterable<String> ids = const [], GraphLayout? layout}) : elementIds = {...ids}, layout = layout ?? GraphLayout();
  final GraphLayout layout;
  final String name;
  int color;
  String? folder;
  final Set<String> elementIds;
}
final memoBoxes = <MemoBox>[];
final memoBoxFolders = <String>[];
/// Moving a thought to a box replaces its previous membership.
void moveThoughtToBox(String id, MemoBox target) {
  for (final box in memoBoxes) { if (!identical(box, target)) box.elementIds.remove(id); }
  target.elementIds.add(id);
}
void replaceBoxThoughts(MemoBox target, Iterable<String> ids) {
  final selected = ids.toSet();
  target.elementIds.clear();
  for (final id in selected) { moveThoughtToBox(id, target); }
}
void normalizeBoxMemberships() {
  final seen = <String>{};
  for (final box in memoBoxes) { box.elementIds.removeWhere((id) => !seen.add(id)); }
}

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
    onAcceptWithDetails: (details) { moveThoughtToBox(details.data.id, box); onChanged(); },
    builder: (context, candidates, rejected) => Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        color: candidates.isEmpty ? null : Color(box.color).withValues(alpha: .25)), child: child));
}

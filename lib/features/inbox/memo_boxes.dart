import 'package:flutter/material.dart';
import 'graph_layout.dart';
import 'element_store.dart';

class MemoBox {
  MemoBox(this.name, {this.color = 0xFF90A4AE, this.folder, this.parentName, this.isUnclassified = false, Iterable<String> ids = const [], GraphLayout? layout}) : _elementIds = {...ids}, layout = layout ?? GraphLayout();
  final GraphLayout layout;
  final String name;
  int color;
  String? folder;
  String? parentName;
  MemoBox? get parent => memoBoxes.where((b) => !b.isUnclassified && b.name == parentName && !identical(b, this)).firstOrNull;
  Iterable<MemoBox> get children => memoBoxes.where((b) => !b.isUnclassified && b.parentName == name && !identical(b, this));
  bool isAncestorOf(MemoBox other) {
    final seen = <MemoBox>{};
    for (var p = other.parent; p != null && seen.add(p); p = p.parent) { if (identical(p, this)) return true; }
    return false;
  }
  int get depth {
    final seen = <MemoBox>{this}; var result = 1;
    for (var p = parent; p != null && seen.add(p); p = p.parent) { result++; }
    return result;
  }
  Set<String> get subtreeElementIds => {...elementIds, for (final b in memoBoxes.where(isAncestorOf)) ...b.elementIds};
  String get path => parent == null ? name : '${parent!.path} / $name';
  final bool isUnclassified;
  final Set<String> _elementIds;
  Set<String> get elementIds => isUnclassified
      ? elements.records.values.map((record) => record.id).toSet().difference(
          memoBoxes.where((box) => !box.isUnclassified).expand((box) => box.elementIds).toSet())
      : _elementIds;
}
final memoBoxes = <MemoBox>[];
final memoBoxFolders = <String>[];
MemoBox ensureUnclassifiedBox() {
  final existing = memoBoxes.where((box) => box.isUnclassified).firstOrNull;
  if (existing != null) return existing;
  final legacy = memoBoxes.where((box) => box.name == '미분류').firstOrNull;
  final box = MemoBox('미분류', isUnclassified: true, color: legacy?.color ?? 0xFF90A4AE, layout: legacy?.layout);
  if (legacy != null) memoBoxes.remove(legacy);
  memoBoxes.insert(0, box);
  return box;
}
/// Moving a thought to a box replaces its previous membership.
void moveThoughtToBox(String id, MemoBox target) {
  for (final box in memoBoxes) { if (!identical(box, target)) box.elementIds.remove(id); }
  if (!target.isUnclassified) target.elementIds.add(id);
}
void normalizeBoxMemberships() {
  final seen = <String>{};
  for (final box in memoBoxes.where((box) => !box.isUnclassified)) { box.elementIds.removeWhere((id) => !seen.add(id)); }
}

bool canParentBox(MemoBox box, MemoBox? parent) {
  if (box.isUnclassified || parent?.isUnclassified == true || identical(box, parent) || (parent != null && box.isAncestorOf(parent))) return false;
  final subtreeHeight = memoBoxes.where(box.isAncestorOf).fold(1, (height, child) => height > child.depth - box.depth + 1 ? height : child.depth - box.depth + 1);
  return (parent?.depth ?? 0) + subtreeHeight <= 3;
}
void setBoxParent(MemoBox box, MemoBox? parent) {
  if (!canParentBox(box, parent)) throw ArgumentError('메모상자는 순환 없이 최대 3단계까지 만들 수 있습니다.');
  box.parentName = parent?.name;
  if (parent != null) box.folder = null;
}
void normalizeBoxHierarchy() {
  for (final box in memoBoxes) {
    if (box.isUnclassified || box.parent == null || box.depth > 3 || box.isAncestorOf(box)) box.parentName = null;
  }
}
Future<bool> editBoxHierarchy(BuildContext context) async {
  var changed = false;
  await showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
    title: const Text('메모상자 구조'),
    content: SizedBox(width: 420, height: 340, child: ListView(children: [
      const Text('상자를 최대 3단계로 중첩할 수 있습니다.', style: TextStyle(fontSize: 12)),
      for (final box in memoBoxes.where((b) => !b.isUnclassified)) ListTile(
        title: Text(box.path, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${box.depth}단계 · 눌러서 상위 상자 변경'),
        onTap: () async {
          final selected = await showDialog<String>(context: context, builder: (context) => SimpleDialog(title: Text('${box.name}의 상위 상자'), children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(context, ''), child: const Text('최상위로')),
            for (final parent in memoBoxes.where((b) => canParentBox(box, b))) SimpleDialogOption(
              onPressed: () => Navigator.pop(context, parent.name), child: Text(parent.path)),
          ]));
          if (selected == null || !context.mounted) return;
          update(() { setBoxParent(box, memoBoxes.where((b) => b.name == selected).firstOrNull); changed = true; });
        },
      ),
    ])), actions: [TextButton(onPressed: () async {
      final box = await createMemoBox(context);
      if (box != null && context.mounted) update(() => changed = true);
    }, child: const Text('상자 만들기')), TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  )));
  return changed;
}

class MemoDrag {
  const MemoDrag(this.id);
  final String id;
}

Future<MemoBox?> createMemoBox(BuildContext context) async {
  var draft = '';
  MemoBox? parent;
  final name = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
    title: const Text('메모상자 만들기'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(autofocus: true, maxLength: 60, onChanged: (value) => draft = value,
      decoration: const InputDecoration(labelText: '상자 이름'),
      onSubmitted: (value) { if (value.trim().isNotEmpty) Navigator.pop(context, value.trim()); }),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: '', decoration: const InputDecoration(labelText: '상위 상자'), isExpanded: true,
        items: [const DropdownMenuItem(value: '', child: Text('최상위')),
          for (final box in memoBoxes.where((b) => !b.isUnclassified && b.depth < 3)) DropdownMenuItem(value: box.name, child: Text(box.path, overflow: TextOverflow.ellipsis))],
        onChanged: (value) => update(() => parent = memoBoxes.where((b) => b.name == value).firstOrNull)),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      TextButton(onPressed: () { if (draft.trim().isNotEmpty) Navigator.pop(context, draft.trim()); }, child: const Text('만들기'))],
  )));
  if (name == null) return null;
  if (name == '미분류') return ensureUnclassifiedBox();
  final existing = memoBoxes.where((box) => box.name == name);
  if (existing.isNotEmpty) return existing.first;
  final box = MemoBox(name, parentName: parent?.name);
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

import 'workspace_photo.dart';
import 'package:flutter/material.dart';
import 'graph_layout.dart';
import 'element_store.dart';

class MemoBox {
  MemoBox(this.name, {this.color = 0xFF90A4AE, this.folder, this.isUnclassified = false, Iterable<String> ids = const [], GraphLayout? layout}) : _elementIds = {...ids}, layout = layout ?? GraphLayout();
  final GraphLayout layout;
  String name;
  int color;
  String? folder;
  final bool isUnclassified;
  final Set<String> _elementIds;
  Set<String> get elementIds => isUnclassified
      ? {...elements.records.values.map((record) => record.id), ...workspacePhotos.keys}.difference(
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

class MemoDrag {
  const MemoDrag(this.id);
  final String id;
}

Future<MemoBox?> createMemoBox(BuildContext context, {String? folder}) async {
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
  if (name == '미분류') return ensureUnclassifiedBox();
  final existing = memoBoxes.where((box) => box.name == name);
  if (existing.isNotEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 사용 중인 상자 이름입니다.')),
      );
    }
    return null;
  }
  final box = MemoBox(name, folder: memoBoxes.any((box) => !box.isUnclassified && box.name == folder) || memoBoxFolders.contains(folder) ? folder : null);
  memoBoxes.add(box);
  return box;
}

MemoBox? parentMemoBox(MemoBox box) => memoBoxes
    .where((candidate) => candidate != box && !candidate.isUnclassified &&
        candidate.name == box.folder)
    .firstOrNull;

Iterable<MemoBox> childMemoBoxes(MemoBox? box) => memoBoxes
    .where((candidate) => !candidate.isUnclassified && parentMemoBox(candidate) == box);

bool memoBoxContains(MemoBox ancestor, MemoBox box) {
  final seen = <MemoBox>{};
  for (MemoBox? current = box; current != null && seen.add(current);
      current = parentMemoBox(current)) {
    if (current == ancestor) return true;
  }
  return false;
}

bool canMoveMemoBox(MemoBox box, MemoBox? parent) {
  final seen = <MemoBox>{box};
  for (var current = parent; current != null; current = parentMemoBox(current)) {
    if (current.isUnclassified || !seen.add(current)) return false;
  }
  return !box.isUnclassified;
}

String memoBoxPath(MemoBox box) {
  final seen = <MemoBox>{};
  final names = <String>[];
  for (MemoBox? current = box; current != null && seen.add(current); current = parentMemoBox(current)) {
    names.add(current.name);
  }
  return names.reversed.join(' / ');
}

Set<String> memoBoxContents(MemoBox box, {required bool includeChildren}) {
  final seen = <MemoBox>{};
  final pending = [box];
  final contents = <String>{};
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!seen.add(current)) continue;
    contents.addAll(current.elementIds);
    if (includeChildren) pending.addAll(childMemoBoxes(current));
  }
  return contents;
}

void convertLegacyMemoFolders() {
  normalizeMemoFolders();
  final names = <String, String>{};
  final occupied = memoBoxes.map((box) => box.name).toSet()..add('미분류');
  for (final folder in memoBoxFolders) {
    var name = folder;
    for (var suffix = 2; occupied.contains(name); suffix++) {
      name = '$folder ($suffix)';
    }
    occupied.add(name);
    names[folder] = name;
  }
  for (final box in memoBoxes) {
    box.folder = names[box.folder] ?? box.folder;
  }
  for (final entry in names.entries) {
    memoBoxes.add(MemoBox(entry.value, folder: names[memoFolderParent(entry.key)]));
  }
  memoBoxFolders.clear();
  memoBoxFolderParents.clear();
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

/// Folder nesting is separate from thought membership: only MemoBox owns IDs.
final memoBoxFolderParents = <String, String>{};
String? memoFolderParent(String folder) {
  final parent = memoBoxFolderParents[folder];
  return parent != folder && memoBoxFolders.contains(parent) ? parent : null;
}
bool memoFolderContains(String ancestor, String folder) {
  final seen = <String>{};
  for (String? current = folder; current != null && seen.add(current); current = memoFolderParent(current)) {
    if (current == ancestor) return true;
  }
  return false;
}
int memoFolderDepth(String folder) {
  final seen = <String>{}; var depth = 0;
  for (String? p = folder; p != null && seen.add(p); p = memoFolderParent(p)) { depth++; }
  return depth;
}
String memoFolderPath(String folder) {
  final parts = <String>[], seen = <String>{};
  for (String? p = folder; p != null && seen.add(p); p = memoFolderParent(p)) { parts.insert(0, p); }
  return parts.join(' / ');
}
bool canMoveMemoFolder(String folder, String? parent) => memoBoxFolders.contains(folder) &&
  (parent == null || (memoBoxFolders.contains(parent) && !memoFolderContains(folder, parent)));
void moveMemoFolder(String folder, String? parent) {
  if (!canMoveMemoFolder(folder, parent)) throw ArgumentError('폴더를 자기 자신이나 하위 폴더 안으로 이동할 수 없습니다.');
  if (parent == null) { memoBoxFolderParents.remove(folder); } else { memoBoxFolderParents[folder] = parent; }
}
void normalizeMemoFolders() {
  memoBoxFolderParents.removeWhere((folder, parent) => !memoBoxFolders.contains(folder) || !memoBoxFolders.contains(parent) || folder == parent);
  for (final folder in memoBoxFolders) {
    final parent = memoFolderParent(folder);
    if (parent != null && memoFolderContains(folder, parent)) memoBoxFolderParents.remove(folder);
  }
}
Future<bool> createMemoFolder(BuildContext context) async {
  var name = ''; String? parent;
  final created = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
    title: const Text('메모상자 폴더 만들기'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(autofocus: true, decoration: const InputDecoration(labelText: '폴더 이름'), onChanged: (value) => name = value.trim(),
        onSubmitted: (value) { if (value.trim().isNotEmpty) { name = value.trim(); Navigator.pop(context, true); } }),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: '', isExpanded: true, decoration: const InputDecoration(labelText: '상위 폴더'),
        items: [const DropdownMenuItem(value: '', child: Text('최상위')), for (final folder in memoBoxFolders)
          DropdownMenuItem(value: folder, child: Text(memoFolderPath(folder), overflow: TextOverflow.ellipsis))],
        onChanged: (value) => update(() => parent = value == '' ? null : value)),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
      TextButton(onPressed: () { if (name.isNotEmpty) Navigator.pop(context, true); }, child: const Text('만들기'))],
  )));
  if (created != true || name.isEmpty || memoBoxFolders.contains(name)) return false;
  memoBoxFolders.add(name); moveMemoFolder(name, parent); return true;
}

class MemoFolderDrag {
  const MemoFolderDrag(this.name);
  final String name;
}

/// Delete only the container; all thoughts remain in the workspace.
void removeMemoBoxesKeepingThoughts(Set<String> names){
  final removed=memoBoxes.where((b)=>!b.isUnclassified&&names.contains(b.name)).toList();
  final ids=removed.expand((b)=>b.elementIds).toSet();
  for (final box in memoBoxes.where((box) => !removed.contains(box))) {
    var parent = parentMemoBox(box);
    final visited = <MemoBox>{box};
    while (parent != null && removed.contains(parent) && visited.add(parent)) {
      parent = parentMemoBox(parent);
    }
    if (removed.any((old) => old.name == box.folder)) {
      box.folder = parent != null && !removed.contains(parent) ? parent.name : null;
    }
  }
  memoBoxes.removeWhere(removed.contains);
  for(final box in memoBoxes.where((b)=>!b.isUnclassified)){box.elementIds.removeAll(ids);}
  ensureUnclassifiedBox();
}
/// Promote direct children by one level, preserving nested folder contents.
void removeMemoFolderKeepingContents(String folder){
  if(!memoBoxFolders.contains(folder))return;
  final parent=memoFolderParent(folder);
  for(final box in memoBoxes){if(box.folder==folder)box.folder=parent;}
  for(final child in memoBoxFolders.where((f)=>memoFolderParent(f)==folder).toList()){
    if(parent==null){memoBoxFolderParents.remove(child);}else{memoBoxFolderParents[child]=parent;}
  }
  memoBoxFolders.remove(folder);memoBoxFolderParents.remove(folder);
}

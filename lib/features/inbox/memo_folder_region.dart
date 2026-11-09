import 'package:flutter/material.dart';
import 'memo_boxes.dart';

Map<String, Rect> memoFolderRegions(Map<MemoBox, Rect> boxes, Map<String, Offset> emptyPositions) {
  final result = <String, Rect>{};
  Rect bounds(String folder) {
    if (result.containsKey(folder)) return result[folder]!;
    final parts = [for (final entry in boxes.entries) if (entry.key.folder == folder) entry.value,
      for (final child in memoBoxFolders.where((f) => memoFolderParent(f) == folder)) bounds(child)];
    final rect = parts.isEmpty
      ? (emptyPositions.putIfAbsent(folder, () => Offset(640 + memoBoxFolders.indexOf(folder) * 360, 1100)) & const Size(300, 200))
      : parts.reduce((a, b) => a.expandToInclude(b));
    return result[folder] = Rect.fromLTRB(rect.left - 28, rect.top - 44, rect.right + 28, rect.bottom + 28);
  }
  for (final folder in memoBoxFolders) { bounds(folder); }
  final ordered = [...result.keys]..sort((a, b) => memoFolderDepth(a).compareTo(memoFolderDepth(b)));
  return {for (final key in ordered) key: result[key]!};
}

/// A background group, deliberately not a `DragTarget<MemoDrag>` or a `MemoBox`.
class MemoFolderRegion extends StatelessWidget {
  const MemoFolderRegion({super.key, required this.name, required this.bounds, required this.onMove, required this.onEnd, required this.onEdit});
  final String name;
  final Rect bounds;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd, onEdit;
  @override
  Widget build(BuildContext context) => Positioned.fromRect(rect: bounds, child: GestureDetector(
    behavior: HitTestBehavior.opaque, onPanUpdate: (d) => onMove(d.delta), onPanEnd: (_) => onEnd(), onPanCancel: onEnd,
    child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .12),
      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .4))),
      child: Align(alignment: Alignment.topLeft, child: TextButton.icon(onPressed: onEdit,
        icon: const Icon(Icons.folder_outlined, size: 16), label: Text(name, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap))),
  )));
}

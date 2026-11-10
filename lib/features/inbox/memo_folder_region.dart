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
class MemoFolderRegion extends StatefulWidget {
  const MemoFolderRegion({super.key, required this.name, required this.bounds, required this.onMove, required this.onEnd, this.onLiftStart, this.onLiftMove, this.onLiftEnd, this.highlighted = false, this.onZoom});
  final String name;
  final Rect bounds;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final ValueChanged<Offset>? onLiftStart, onLiftMove, onLiftEnd;
  final bool highlighted;
  final void Function(double scale, Offset focal)? onZoom;
  @override
  State<MemoFolderRegion> createState() => _MemoFolderRegionState();
}
class _MemoFolderRegionState extends State<MemoFolderRegion> {
  Offset? _lastGlobal;
  bool _pinching = false, _scaling = false;
  @override
  Widget build(BuildContext context) => Positioned.fromRect(rect: widget.bounds, child: Listener(
    onPointerDown: (event) { _lastGlobal ??= event.position; },
    onPointerUp: (_) { if (!_scaling) _lastGlobal = null; },
    onPointerCancel: (_) { if (!_scaling) _lastGlobal = null; },
    child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: widget.onLiftStart == null ? null : (d) => widget.onLiftStart!(d.globalPosition),
    onLongPressMoveUpdate: widget.onLiftMove == null ? null : (d) => widget.onLiftMove!(d.globalPosition),
    onLongPressEnd: widget.onLiftEnd == null ? null : (d) => widget.onLiftEnd!(d.globalPosition),
    onScaleStart: (d) { _scaling = true; _lastGlobal ??= d.focalPoint; },
    onScaleUpdate: (d) {
      if (d.pointerCount > 1) { _pinching = true; widget.onZoom?.call(d.scale, d.focalPoint); }
      else if (!_pinching && _lastGlobal != null) {
        final box = context.findRenderObject() as RenderBox;
        widget.onMove(box.globalToLocal(d.focalPoint) - box.globalToLocal(_lastGlobal!));
      }
      _lastGlobal = d.focalPoint;
    }, onScaleEnd: (_) { _lastGlobal = null; _pinching = false; _scaling = false; widget.onEnd(); },
    child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .12),
      border: Border.all(color: widget.highlighted ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withValues(alpha: .4), width: widget.highlighted ? 3 : 1)),
      child: Align(alignment: Alignment.topLeft, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_outlined, size: 16), const SizedBox(width: 6),
          Flexible(child: Text(widget.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        ]))),
  ))));
}

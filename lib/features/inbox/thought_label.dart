import 'package:flutter/material.dart';
import 'element_store.dart';

/// The paper is translucent; the single-line title remains opaque.
class ThoughtLabel extends StatelessWidget {
  const ThoughtLabel({super.key, required this.record, required this.onHold, this.active = false});
  final ElementRecord record;
  final ValueChanged<bool> onHold;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final paper = Color(record.indexLabelColor).withValues(alpha: .6);
    final blended = Color.alphaBlend(paper, Theme.of(context).colorScheme.surface);
    final ink = blended.computeLuminance() < .35 ? Colors.white : const Color(0xFF202020);
    return Tooltip(message: record.indexLabel,
    child: Listener(behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onHold(true), onPointerUp: (_) => onHold(false), onPointerCancel: (_) => onHold(false),
      child: Material(color: Colors.transparent, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: paper,
          borderRadius: BorderRadius.circular(3),
          border: active ? Border.all(color: Theme.of(context).colorScheme.primary) : null),
        child: Text(record.indexLabel, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ))));
  }
}

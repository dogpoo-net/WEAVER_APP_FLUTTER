import 'package:flutter/material.dart';
import 'element_store.dart';

/// Candidates are ordered from back to front; equal overlap favors the front.
String? labelOverlapTarget(Rect label, List<({String id, Rect bounds})> candidates) {
  String? target;
  double largest = 0;
  for (final candidate in candidates) {
    final overlap = label.intersect(candidate.bounds);
    final area = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
    if (area > 0 && area >= largest) { largest = area; target = candidate.id; }
  }
  return target;
}

/// The paper is translucent; the single-line title remains opaque.
class ThoughtLabel extends StatelessWidget {
  const ThoughtLabel({super.key, required this.record, required this.onHold, this.active = false, this.movable = false});
  final ElementRecord record;
  final ValueChanged<bool> onHold;
  final bool active, movable;
  static double width(BuildContext context, String text) {
    final painter = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
    final width = painter.width + 20;
    painter.dispose();
    return width;
  }
  static double height(BuildContext context, String text) {
    final painter=TextPainter(text:TextSpan(text:text,style:DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize:12,fontWeight:FontWeight.w600))),
      textDirection:Directionality.of(context),textScaler:MediaQuery.textScalerOf(context),maxLines:1)..layout();
    final height=painter.height+10; painter.dispose(); return height;
  }
  @override
  Widget build(BuildContext context) {
    final paper = Color(record.indexLabelColor).withValues(alpha: .6);
    final blended = Color.alphaBlend(paper, Theme.of(context).colorScheme.surface);
    final ink = blended.computeLuminance() < .35 ? Colors.white : const Color(0xFF202020);
    return Tooltip(message: record.indexLabel, triggerMode: movable ? TooltipTriggerMode.manual : null,
    child: Listener(key: ValueKey('label-hold-${record.id}'), behavior: HitTestBehavior.opaque,
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

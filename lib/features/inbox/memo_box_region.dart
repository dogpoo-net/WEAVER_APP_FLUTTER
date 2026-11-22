import 'package:flutter/material.dart';
import 'memo_boxes.dart';

bool memoBoxRegionsOverlap(Rect a, Rect b, {double gap = 24}) =>
    a.inflate(gap).overlaps(b);

class MemoBoxRegion extends StatelessWidget {
  const MemoBoxRegion({super.key, required this.box, required this.bounds, this.onDrag, this.onDragEnd, this.onDragCancel, this.onLiftStart, this.onLiftMove, this.onLiftEnd, this.highlighted = false, this.showLabel=true});
  final MemoBox box;
  final Rect bounds;
  final bool highlighted, showLabel;
  final ValueChanged<Offset>? onDrag, onLiftStart, onLiftMove, onLiftEnd;
  final VoidCallback? onDragEnd, onDragCancel;
  @override
  Widget build(BuildContext context) => Positioned.fromRect(rect: bounds, child: ClipRRect(borderRadius: BorderRadius.circular(24),
    child: GestureDetector(behavior: HitTestBehavior.opaque,
      onLongPressStart: onLiftStart == null ? null : (d) => onLiftStart!(d.globalPosition),
      onLongPressMoveUpdate: onLiftMove == null ? null : (d) => onLiftMove!(d.globalPosition),
      onLongPressEnd: onLiftStart == null ? null : (d) => onLiftEnd != null ? onLiftEnd!(d.globalPosition) : onDragEnd?.call(),
      onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta), onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(), onPanCancel: onDragCancel ?? onDragEnd,
      child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
        color: Color(box.color).withValues(alpha: highlighted ? .16 : .10),
        border: Border.all(color: Color(box.color).withValues(alpha: .7), width: highlighted ? 3 : 1.5)),
        child: !showLabel?null:Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(32, 15, 32, 0),
          child: Text(box.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(box.color), fontSize: 13, fontWeight: FontWeight.w600)))),
      ),
    ),
  ));
}

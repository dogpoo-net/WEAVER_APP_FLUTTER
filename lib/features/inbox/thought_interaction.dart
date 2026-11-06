import 'package:flutter/material.dart';

class ThoughtInteraction extends StatefulWidget {
  const ThoughtInteraction({super.key, required this.size, required this.child,
    required this.onMove, required this.onResize, required this.onDrop, required this.onEnd,
    required this.onTap, required this.onDoubleTap, required this.desktop, this.onLift, this.onActiveChanged});
  final Size size;
  final Widget child;
  final ValueChanged<Offset> onMove, onDrop;
  final void Function(Size size, Offset shift) onResize;
  final VoidCallback onEnd, onTap, onDoubleTap;
  final bool desktop;
  final VoidCallback? onLift;
  final ValueChanged<bool>? onActiveChanged;
  @override
  State<ThoughtInteraction> createState() => _ThoughtInteractionState();
}
class _ThoughtInteractionState extends State<ThoughtInteraction> {
  Size _start = Size.zero;
  Offset _pointer = Offset.zero;
  bool _resized = false, _lifted = false;
  Offset _longOffset = Offset.zero;
  Size _clamp(double w, double h) => Size(w.clamp(170, 640), h.clamp(76, 520));
  Widget _handle(String name, MouseCursor cursor, bool left, bool top, bool horizontal, bool vertical) =>
    MouseRegion(cursor: cursor, child: GestureDetector(key: ValueKey('resize-$name'), behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final next = _clamp(widget.size.width + (horizontal ? d.delta.dx * (left ? -1 : 1) : 0),
          widget.size.height + (vertical ? d.delta.dy * (top ? -1 : 1) : 0));
        widget.onResize(next, Offset(left ? widget.size.width - next.width : 0, top ? widget.size.height - next.height : 0));
      }, onPanEnd: (_) => widget.onEnd(), child: const SizedBox.expand()));
  @override
  Widget build(BuildContext context) => GestureDetector(behavior: HitTestBehavior.opaque,
    onTap: widget.onTap, onDoubleTap: widget.onDoubleTap,
    onLongPressStart: widget.onLift == null ? null : (d) {
      _longOffset = d.globalPosition; setState(() => _lifted = true);
      widget.onLift!(); widget.onActiveChanged?.call(true);
    },
    onLongPressMoveUpdate: widget.onLift == null ? null : (d) {
      final box = context.findRenderObject() as RenderBox;
      widget.onMove(box.globalToLocal(d.globalPosition) - box.globalToLocal(_longOffset));
      _longOffset = d.globalPosition;
    },
    onLongPressEnd: widget.onLift == null ? null : (d) {
      widget.onDrop(d.globalPosition); setState(() => _lifted = false);
      widget.onActiveChanged?.call(false); widget.onEnd();
    },
    onLongPressCancel: () { if (_lifted) { setState(() => _lifted = false); widget.onActiveChanged?.call(false); widget.onEnd(); } },
    onScaleStart: (d) { _start = widget.size; _pointer = d.focalPoint; _resized = false; widget.onActiveChanged?.call(true); },
    onScaleUpdate: (d) {
      _pointer = d.focalPoint;
      if (d.pointerCount >= 2) {
        _resized = true;
        widget.onResize(_clamp(_start.width * d.scale, _start.height * d.scale), Offset.zero);
      } else if (!_resized) { widget.onMove(d.focalPointDelta); }
    },
    onScaleEnd: (_) { if (!_resized) widget.onDrop(_pointer); widget.onActiveChanged?.call(false); widget.onEnd(); },
    child: SizedBox(width: widget.size.width, height: widget.size.height, child: Stack(fit: StackFit.expand, children: [
      AnimatedScale(scale: _lifted ? 1.04 : 1, duration: const Duration(milliseconds: 100), child: widget.child),
      if (widget.desktop) ...[
        Positioned(left: 0, top: 10, bottom: 10, width: 8, child: _handle('left', SystemMouseCursors.resizeLeftRight, true, false, true, false)),
        Positioned(right: 0, top: 10, bottom: 10, width: 8, child: _handle('right', SystemMouseCursors.resizeLeftRight, false, false, true, false)),
        Positioned(top: 0, left: 10, right: 10, height: 8, child: _handle('top', SystemMouseCursors.resizeUpDown, false, true, false, true)),
        Positioned(bottom: 0, left: 10, right: 10, height: 8, child: _handle('bottom', SystemMouseCursors.resizeUpDown, false, false, false, true)),
        for (final left in [true, false]) for (final top in [true, false]) Positioned(
          left: left ? 0 : null, right: left ? null : 0, top: top ? 0 : null, bottom: top ? null : 0, width: 12, height: 12,
          child: _handle('${left ? 'left' : 'right'}-${top ? 'top' : 'bottom'}',
            left == top ? SystemMouseCursors.resizeUpLeftDownRight : SystemMouseCursors.resizeUpRightDownLeft,
            left, top, true, true)),
      ],
    ])),
  );
}

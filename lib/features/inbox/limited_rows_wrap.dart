import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Uses actual laid-out badge heights, including text scaling, to cap rows.
class LimitedRowsWrap extends Wrap {
  const LimitedRowsWrap({super.key, required super.children, this.maxRows = 5, this.onOverflowChanged})
    : super(spacing: 6, runSpacing: 6);
  final int maxRows;
  final ValueChanged<bool>? onOverflowChanged;
  @override
  RenderWrap createRenderObject(BuildContext context) => _LimitedRowsRenderWrap(maxRows, Directionality.of(context), onOverflowChanged);
  @override
  void updateRenderObject(BuildContext context, covariant RenderWrap renderObject) {
    super.updateRenderObject(context, renderObject);
    final limited = renderObject as _LimitedRowsRenderWrap;
    limited.maxRows = maxRows;
    limited.onOverflowChanged = onOverflowChanged;
  }
}
class _LimitedRowsRenderWrap extends RenderWrap {
  _LimitedRowsRenderWrap(this._maxRows, TextDirection direction, this.onOverflowChanged) : super(spacing: 6, runSpacing: 6, textDirection: direction);
  int _maxRows;
  ValueChanged<bool>? onOverflowChanged;
  bool? _lastOverflow;
  set maxRows(int value) { if (_maxRows != value) { _maxRows = value; markNeedsLayout(); } }
  @override
  void performLayout() {
    super.performLayout();
    var child = firstChild;
    var rows = 0;
    double? previousTop;
    var bottom = 0.0;
    while (child != null) {
      final data = child.parentData! as WrapParentData;
      if (previousTop == null || (data.offset.dy - previousTop).abs() > .1) {
        rows++; previousTop = data.offset.dy;
      }
      if (rows > _maxRows) break;
      bottom = math.max(bottom, data.offset.dy + child.size.height);
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(size.width, bottom));
    final overflow = rows > _maxRows;
    if (_lastOverflow != overflow) {
      _lastOverflow = overflow;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (attached) onOverflowChanged?.call(overflow); });
    }
  }
}

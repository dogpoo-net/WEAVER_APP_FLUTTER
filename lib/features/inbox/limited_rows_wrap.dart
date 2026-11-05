import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Uses actual laid-out badge heights, including text scaling, to cap rows.
class LimitedRowsWrap extends Wrap {
  const LimitedRowsWrap({super.key, required super.children, this.maxRows = 5})
    : super(spacing: 6, runSpacing: 6);
  final int maxRows;
  @override
  RenderWrap createRenderObject(BuildContext context) => _LimitedRowsRenderWrap(maxRows, Directionality.of(context));
  @override
  void updateRenderObject(BuildContext context, covariant RenderWrap renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _LimitedRowsRenderWrap).maxRows = maxRows;
  }
}
class _LimitedRowsRenderWrap extends RenderWrap {
  _LimitedRowsRenderWrap(this._maxRows, TextDirection direction) : super(spacing: 6, runSpacing: 6, textDirection: direction);
  int _maxRows;
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
  }
}

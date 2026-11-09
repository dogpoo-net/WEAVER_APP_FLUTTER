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
  final _visible = <RenderBox>[];
  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _visible) {
      context.paintChild(child, offset + (child.parentData! as WrapParentData).offset);
    }
  }
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _visible.reversed) {
      if (result.addWithPaintOffset(offset: (child.parentData! as WrapParentData).offset,
        position: position, hitTest: (result, transformed) => child.hitTest(result, position: transformed))) return true;
    }
    return false;
  }
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in _visible) { visitor(child); }
  }
  @override
  void performLayout() {
    _visible.clear();
    final rows = <List<RenderBox>>[];
    final widths = <double>[], heights = <double>[];
    var row = <RenderBox>[];
    var width = 0.0, height = 0.0;
    var child = firstChild;
    var overflow = false;
    final childConstraints = BoxConstraints(maxWidth: constraints.maxWidth);
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      final nextWidth = width + (row.isEmpty ? 0 : spacing) + child.size.width;
      if (row.isNotEmpty && nextWidth > constraints.maxWidth) {
        rows.add(row); widths.add(width); heights.add(height);
        if (rows.length >= _maxRows) { overflow = true; row = []; break; }
        row = []; width = 0; height = 0;
      }
      width += (row.isEmpty ? 0 : spacing) + child.size.width;
      height = math.max(height, child.size.height);
      row.add(child);
      child = (child.parentData! as WrapParentData).nextSibling;
    }
    if (row.isNotEmpty) { rows.add(row); widths.add(width); heights.add(height); }
    size = constraints.constrain(Size(
      widths.fold(0.0, math.max),
      heights.fold(0.0, (sum, h) => sum + h) + math.max(0, rows.length - 1) * runSpacing));
    var y = 0.0;
    for (var i = 0; i < rows.length; i++) {
      var x = 0.0;
      for (final item in rows[i]) {
        (item.parentData! as WrapParentData).offset = Offset(
          textDirection == TextDirection.rtl ? size.width - x - item.size.width : x, y);
        x += item.size.width + spacing;
        _visible.add(item);
      }
      y += heights[i] + runSpacing;
    }
    markNeedsSemanticsUpdate();
    if (_lastOverflow != overflow) {
      _lastOverflow = overflow;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (attached) onOverflowChanged?.call(overflow); });
    }
  }
}

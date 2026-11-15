import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Packs badges into available rectangles rather than giving each row the
/// height of its tallest badge. Short badges can stack beside multiline ones.
class PackedBadges extends MultiChildRenderObjectWidget {
  const PackedBadges({super.key, required super.children, this.maxRows, this.onOverflowChanged});
  final int? maxRows;
  final ValueChanged<bool>? onOverflowChanged;
  @override RenderObject createRenderObject(BuildContext context) => RenderPackedBadges(Directionality.of(context), maxRows, onOverflowChanged, math.max(30, MediaQuery.textScalerOf(context).scale(12) * 1.5 + 10));
  @override void updateRenderObject(BuildContext context, covariant RenderPackedBadges renderObject) {
    renderObject..direction=Directionality.of(context)..rows=maxRows..rowHeight=math.max(30, MediaQuery.textScalerOf(context).scale(12) * 1.5 + 10)..onOverflowChanged=onOverflowChanged..markNeedsLayout();
  }
}
class _Data extends ContainerBoxParentData<RenderBox> {}
class RenderPackedBadges extends RenderBox with ContainerRenderObjectMixin<RenderBox,_Data>, RenderBoxContainerDefaultsMixin<RenderBox,_Data> {
  RenderPackedBadges(this.direction,this.rows,this.onOverflowChanged,this.rowHeight);
  double rowHeight;
  TextDirection direction;
  int? rows;
  ValueChanged<bool>? onOverflowChanged;
  bool? overflow;
  final visible=<RenderBox>[];
  @override void setupParentData(RenderBox child) { if(child.parentData is! _Data) child.parentData=_Data(); }
  @override void performLayout() {
    visible.clear();
    final width=constraints.maxWidth;
    var limit=rows==null?double.infinity:(rowHeight+6)*rows!-6;
    final free=<Rect>[Rect.fromLTWH(0,0,width,double.infinity)];
    var bottom=0.0, hidden=false;
    for(var child=firstChild;child!=null;child=(child.parentData! as _Data).nextSibling) {
      child.layout(BoxConstraints(maxWidth:width),parentUsesSize:true);
      if(visible.isEmpty)limit=math.max(limit,child.size.height);
      // Join adjacent empty columns once their top edges line up again.
      free.sort((a,b)=>a.top==b.top?a.left.compareTo(b.left):a.top.compareTo(b.top));
      for(var i=free.length-2;i>=0;i--){
        final a=free[i],b=free[i+1];
        if((a.top-b.top).abs()<.01 && a.height==b.height && (a.right+6-b.left).abs()<.01){
          free[i]=Rect.fromLTWH(a.left,a.top,b.right-a.left,a.height);free.removeAt(i+1);
        }
      }
      free.sort((a,b)=>a.top==b.top?a.left.compareTo(b.left):a.top.compareTo(b.top));
      final childSize=child.size;
      final index=free.indexWhere((r)=>r.width+.01>=childSize.width && r.height+.01>=childSize.height);
      final slot=index<0?Rect.fromLTWH(0,bottom+6,width,double.infinity):free.removeAt(index);
      if(index<0)free.clear();
      if(slot.top+child.size.height>limit+.01){hidden=true;break;}
      final x=slot.left,y=slot.top,w=child.size.width,h=child.size.height;
      (child.parentData! as _Data).offset=Offset(direction==TextDirection.rtl?width-x-w:x,y);
      visible.add(child);bottom=math.max(bottom,y+h);
      if(slot.width>w+6)free.add(Rect.fromLTWH(x+w+6,y,slot.width-w-6,slot.height));
      if(slot.height>h+6)free.add(Rect.fromLTWH(x,y+h+6,math.min(slot.width,w),slot.height.isInfinite?double.infinity:slot.height-h-6));
    }
    size=constraints.constrain(Size(width,bottom));markNeedsSemanticsUpdate();
    if(overflow!=hidden){overflow=hidden;WidgetsBinding.instance.addPostFrameCallback((_){if(attached)onOverflowChanged?.call(hidden);});}
  }
  @override void paint(PaintingContext context,Offset offset){for(final child in visible){context.paintChild(child,offset+(child.parentData! as _Data).offset);}}
  @override bool hitTestChildren(BoxHitTestResult result,{required Offset position}){for(final child in visible.reversed){if(result.addWithPaintOffset(offset:(child.parentData! as _Data).offset,position:position,hitTest:(r,p)=>child.hitTest(r,position:p)))return true;}return false;}
  @override void visitChildrenForSemantics(RenderObjectVisitor visitor){for(final child in visible){visitor(child);}}
}

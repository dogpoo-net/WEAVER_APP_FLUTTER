import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Packs badges into available rectangles rather than giving each row the
/// height of its tallest badge. Short badges can stack beside multiline ones.
class PackedBadges extends MultiChildRenderObjectWidget {
  const PackedBadges({super.key, required super.children, this.maxRows, this.alwaysVisibleCount = 0, this.onOverflowChanged});
  final int? maxRows;
  final int alwaysVisibleCount;
  final ValueChanged<bool>? onOverflowChanged;
  @override RenderObject createRenderObject(BuildContext context) => RenderPackedBadges(Directionality.of(context), maxRows, onOverflowChanged, math.max(30, MediaQuery.textScalerOf(context).scale(12) * 1.5 + 10), alwaysVisibleCount:alwaysVisibleCount);
  @override void updateRenderObject(BuildContext context, covariant RenderPackedBadges renderObject) {
    final direction=Directionality.of(context),height=math.max(30.0,MediaQuery.textScalerOf(context).scale(12)*1.5+10);
    final changed=renderObject.direction!=direction||renderObject.rows!=maxRows||renderObject.alwaysVisibleCount!=alwaysVisibleCount||renderObject.rowHeight!=height;
    renderObject..direction=direction..rows=maxRows..alwaysVisibleCount=alwaysVisibleCount..rowHeight=height..onOverflowChanged=onOverflowChanged;
    if(changed)renderObject.markNeedsLayout();
  }
}
class _Data extends ContainerBoxParentData<RenderBox> {}
class RenderPackedBadges extends RenderBox with ContainerRenderObjectMixin<RenderBox,_Data>, RenderBoxContainerDefaultsMixin<RenderBox,_Data> {
  RenderPackedBadges(this.direction,this.rows,this.onOverflowChanged,this.rowHeight,{this.alwaysVisibleCount=0});
  double rowHeight;
  TextDirection direction;
  int? rows;
  int alwaysVisibleCount;
  ValueChanged<bool>? onOverflowChanged;
  bool? overflow;
  final visible=<RenderBox>[];
  @override void setupParentData(RenderBox child) { if(child.parentData is! _Data) child.parentData=_Data(); }
  @override void performLayout() {
    visible.clear();
    final width=constraints.maxWidth;
    var limit=rows==null?double.infinity:(rowHeight+6)*rows!-6;
    // Reserve spacing inside each occupied rectangle; the outer right gap
    // lies outside the viewport so a full-width badge still fits.
    final free=<Rect>[Rect.fromLTWH(0,0,width+6,double.infinity)];
    var bottom=0.0, hidden=false;
    var index=0;
    for(var child=firstChild;child!=null;child=(child.parentData! as _Data).nextSibling) {
      child.layout(BoxConstraints(maxWidth:width),parentUsesSize:true);
      if(visible.isEmpty)limit=math.max(limit,child.size.height);
      free.sort((a,b)=>a.top==b.top?a.left.compareTo(b.left):a.top.compareTo(b.top));
      final childSize=child.size;
      final slot=free.firstWhere((r)=>r.width+.01>=childSize.width+6 && r.height+.01>=childSize.height+6);
      if(index++<alwaysVisibleCount)limit=math.max(limit,slot.top+child.size.height);
      if(slot.top+child.size.height>limit+.01){hidden=true;continue;}
      final x=slot.left,y=slot.top,w=child.size.width,h=child.size.height;
      (child.parentData! as _Data).offset=Offset(direction==TextDirection.rtl?width-x-w:x,y);
      visible.add(child);bottom=math.max(bottom,y+h);
      final used=Rect.fromLTWH(x,y,w+6,h+6);
      // Keep every maximal empty rectangle, including spaces spanning several
      // earlier narrow columns. A later wide badge can use that combined space.
      final next=<Rect>[];
      for(final r in free){
        if(!r.overlaps(used)){next.add(r);continue;}
        if(used.left>r.left)next.add(Rect.fromLTRB(r.left,r.top,used.left,r.bottom));
        if(used.right<r.right)next.add(Rect.fromLTRB(used.right,r.top,r.right,r.bottom));
        if(used.top>r.top)next.add(Rect.fromLTRB(r.left,r.top,r.right,used.top));
        if(used.bottom<r.bottom)next.add(Rect.fromLTRB(r.left,used.bottom,r.right,r.bottom));
      }
      free.clear();
      for(var i=0;i<next.length;i++){
        final r=next[i];
        if(r.width<.01||r.height<.01)continue;
        var contained=false;
        for(var j=0;j<next.length;j++){
          if(i==j)continue;final other=next[j];
          if(other.left<=r.left&&other.top<=r.top&&other.right>=r.right&&other.bottom>=r.bottom&&
            (other!=r||j<i)){contained=true;break;}
        }
        if(!contained)free.add(r);
      }
    }
    size=constraints.constrain(Size(width,bottom));markNeedsSemanticsUpdate();
    if(overflow!=hidden){overflow=hidden;WidgetsBinding.instance.addPostFrameCallback((_){if(attached)onOverflowChanged?.call(hidden);});}
  }
  @override void paint(PaintingContext context,Offset offset){for(final child in visible){context.paintChild(child,offset+(child.parentData! as _Data).offset);}}
  @override bool hitTestChildren(BoxHitTestResult result,{required Offset position}){for(final child in visible.reversed){if(result.addWithPaintOffset(offset:(child.parentData! as _Data).offset,position:position,hitTest:(r,p)=>child.hitTest(r,position:p)))return true;}return false;}
  @override void visitChildrenForSemantics(RenderObjectVisitor visitor){for(final child in visible){visitor(child);}}
}

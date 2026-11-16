import 'dart:ui';

/// Input is back-to-front paint order. Only rectangles in shared spatial cells
/// can cover each other; distant cards never need a pairwise intersection test.
Set<int> coveredCanvasItems(List<Rect> bounds){
  const cellSize=256.0;
  final cells=<(int,int),List<int>>{},covered=<int>{};
  for(var i=bounds.length-1;i>=0;i--){
    final rect=bounds[i];
    if(rect.isEmpty||!rect.isFinite)continue;
    final left=(rect.left/cellSize).floor(),right=(rect.right/cellSize).floor(),top=(rect.top/cellSize).floor(),bottom=(rect.bottom/cellSize).floor();
    var found=false;
    for(var x=left;x<=right&&!found;x++){
      for(var y=top;y<=bottom&&!found;y++){
        for(final j in cells[(x,y)]??const <int>[]){if(rect.overlaps(bounds[j])){covered.add(i);found=true;break;}}
      }
    }
    for(var x=left;x<=right;x++){for(var y=top;y<=bottom;y++){cells.putIfAbsent((x,y),()=>[]).add(i);}}
  }
  return covered;
}

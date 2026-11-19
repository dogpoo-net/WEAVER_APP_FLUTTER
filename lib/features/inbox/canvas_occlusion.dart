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

/// Finds possible occluders near a card without scanning every later card.
class CanvasOverlapIndex {
  CanvasOverlapIndex(this.bounds) {
    for (var index = 0; index < bounds.length; index++) {
      for (final cell in _cellsFor(bounds[index])) {
        _cells.putIfAbsent(cell, () => []).add(index);
      }
    }
  }

  final List<Rect> bounds;
  final _cells = <(int, int), List<int>>{};

  Iterable<(int, int)> _cellsFor(Rect rect) sync* {
    if (rect.isEmpty || !rect.isFinite) return;
    const cellSize = 256.0;
    for (var x = (rect.left / cellSize).floor(); x <= (rect.right / cellSize).floor(); x++) {
      for (var y = (rect.top / cellSize).floor(); y <= (rect.bottom / cellSize).floor(); y++) {
        yield (x, y);
      }
    }
  }

  List<Rect> overlappingAbove(int index) {
    final rect = bounds[index];
    final matches = <int>{};
    for (final cell in _cellsFor(rect)) {
      for (final other in _cells[cell] ?? const <int>[]) {
        if (other > index && rect.overlaps(bounds[other])) matches.add(other);
      }
    }
    final ordered = matches.toList()..sort();
    return [for (final other in ordered) bounds[other]];
  }
}

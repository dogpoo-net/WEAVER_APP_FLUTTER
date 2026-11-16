import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_occlusion.dart';
Set<int> reference(List<Rect> bounds){
 final result=<int>{};
 for(var i=0;i<bounds.length;i++){for(var j=i+1;j<bounds.length;j++){if(bounds[i].overlaps(bounds[j])){result.add(i);break;}}}
 return result;
}
void main(){
 test('spatial coverage preserves overlapping, edge-touching and paint-order semantics',(){
  final random=Random(42);
  for(var trial=0;trial<30;trial++){
   final bounds=List.generate(150,(_)=>Rect.fromLTWH(random.nextDouble()*3000-500,random.nextDouble()*3000-500,170+random.nextDouble()*470,76+random.nextDouble()*444));
   expect(coveredCanvasItems(bounds),reference(bounds));
  }
  expect(coveredCanvasItems([const Rect.fromLTWH(0,0,256,256),const Rect.fromLTWH(256,0,256,256)]),isEmpty);
 });
 test('measure sparse canvas overlap checking',(){
  final bounds=List.generate(2000,(i)=>Rect.fromLTWH((i%50)*300.0,(i~/50)*200.0,170,76));
  final oldTimes=<int>[],newTimes=<int>[];
  for(var i=0;i<9;i++){
   final watch=Stopwatch()..start();final old=reference(bounds);watch.stop();oldTimes.add(watch.elapsedMicroseconds);
   watch..reset()..start();final next=coveredCanvasItems(bounds);watch.stop();newTimes.add(watch.elapsedMicroseconds);expect(next,old);
  }
  oldTimes.sort();newTimes.sort();
  // Timing is diagnostic, never a machine-dependent pass/fail assertion.
  // ignore: avoid_print
  print('OCCLUSION_BENCH count=2000 baseline_us=${oldTimes[4]} spatial_us=${newTimes[4]}');
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/canvas_geometry.dart';
import 'package:weaver/features/inbox/graph_layout.dart';

void main(){
 test('resized stacks persist without capturing incidental neighbors',(){
 final layout=GraphLayout();
 layout.positions.addAll({'a':const Offset(500,500),'b':const Offset(450,550),'c':const Offset(450,582)});
 layout.stackGroups.addAll({'a':'original','b':'original','c':'separate'});
 final restored=GraphLayout.fromJson(layout.toJson());
 expect(alignedStackMembers('b',restored.positions,groups:restored.stackGroups),{'a','b'});
 reorderStackPositions(restored.positions,{'b'},up:true,groups:restored.stackGroups);
 expect(restored.positions['b'],const Offset(500,500));
 expect(restored.positions['a'],const Offset(450,550));
 expect(restored.positions['c'],const Offset(450,582));
 });
 test('remote stack membership merges without losing local edits',(){
 final base=GraphLayout()..stackGroups.addAll({'a':'one','b':'one','c':'two'});
 final local=GraphLayout.fromJson(base.toJson())..stackGroups['a']='local';
 final remote=GraphLayout.fromJson(base.toJson())..stackGroups['b']='remote';
 local.mergeRemote(remote,base);
 expect(local.stackGroups,{'a':'local','b':'remote','c':'two'});
 final copy=GraphLayout()..copyFrom(local);
 expect(copy.stackGroups,local.stackGroups);
 });
}

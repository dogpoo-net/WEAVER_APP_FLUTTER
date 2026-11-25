import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/workspace_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/thought_interaction.dart';
import 'package:weaver/features/inbox/thought_page.dart';

void main() {
  testWidgets('dropping a canvas photo attaches and pins the original media', (tester) async {
    elements.clear();
    workspacePhotos.clear();
    final layout = (pageGraphLayout = GraphLayout()).blockLayout;
    final thought = elements.add('photo target');
    const attachment = PhotoAttachment('photo-test', 'sample.png');
    workspacePhotos[attachment.id] = WorkspacePhoto(attachment, DateTime.now(), 2);
    layout.positions.addAll({thought.id: const Offset(500,500), attachment.id: const Offset(850,500)});
    await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    final node = tester.widget<ThoughtInteraction>(find.byKey(ValueKey('canvas-thought-${attachment.id}')));
    final target = tester.getCenter(find.byKey(ValueKey('canvas-thought-${thought.id}')));
    node.onActiveChanged!(true);
    node.onMove(const Offset(-350,0));
    node.onDrop(target);
    node.onEnd();
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    expect(workspacePhotos, isEmpty);
    expect(thought.photos.single.id, attachment.id);
    expect(PhotoAttachment.fromJson(thought.photos.single.toJson()).canvasSize, 48);
    expect(find.byKey(ValueKey('canvas-thought-${attachment.id}')), findsNothing);
  });
  for (var slot = 0; slot <= 3; slot++) {
    testWidgets('outside card can enter stack slot $slot', (tester) async {
      elements.clear();
      final layout = (pageGraphLayout = GraphLayout()).blockLayout;
      final ids = [for (var i = 0; i < 3; i++) elements.add('stack $i').id];
      final moving = elements.add('moving').id;
      for (var i = 0; i < ids.length; i++) {
        layout.positions[ids[i]] = Offset(500, 500 + i * 32);
        layout.stackGroups[ids[i]] = 'stack';
      }
      layout.positions[moving] = const Offset(850, 500);
      await tester.pumpWidget(MaterialApp(home: ThoughtPage(onChanged: () {})));
      await tester.pumpAndSettle();
      final finder = find.byKey(ValueKey('canvas-thought-$moving'));
      final node = tester.widget<ThoughtInteraction>(finder);
      node.onActiveChanged!(true);
      node.onMove(Offset(-350, slot * 32));
      await tester.pump();
      node.onDrop(tester.getCenter(finder));
      node.onEnd();
      await tester.pumpAndSettle();
      final ordered = [...ids]..insert(slot, moving);
      for (var i = 0; i < ordered.length; i++) {
        expect(layout.positions[ordered[i]], Offset(500, 500 + i * 32));
      }
    });
  }
}

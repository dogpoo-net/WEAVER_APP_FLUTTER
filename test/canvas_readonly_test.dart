import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/thought_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  for (final blocks in [true]) {
    testWidgets('read-only canvas pans and zooms without editing ($blocks)', (tester) async {
      tester.view.physicalSize = const Size(1200,900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      elements.clear(); memoBoxes.clear(); pageGraphLayout=GraphLayout();
      final memo=elements.add('읽기 전용 메모');
      SharedPreferences.setMockInitialValues({});
      final storage=WorkspaceStorage(await SharedPreferences.getInstance());
      storage.canvasWritable=false;
      storage.documentLease=(id,token,release) async => release?{'released':true}:{'acquired':false,'holder':'다른 사용자'};
      var changed=0;
      await tester.pumpWidget(MaterialApp(home:ThoughtPage(storage:storage,onChanged:()=>changed++)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-readonly-notice')),findsOneWidget);
      expect(find.text('읽기 전용 워크스페이스입니다.'),findsOneWidget);
      expect(find.text('선택'),findsNothing);
      final viewer=tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final transform=viewer.transformationController!;
      final original=List<double>.of(transform.value.storage);
      final card=find.byKey(ValueKey('canvas-thought-${memo.id}'));
      await tester.tapAt(tester.getCenter(card)); await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      await tester.dragFrom(tester.getCenter(card),const Offset(80,35));await tester.pumpAndSettle();
      expect(transform.value.storage, isNot(original));
      final zoom=transform.value.storage[0];
      await tester.sendEventToBinding(PointerScrollEvent(position:tester.getCenter(find.byType(InteractiveViewer)),scrollDelta:const Offset(0,-150)));
      await tester.pumpAndSettle();expect(transform.value.storage[0],isNot(zoom));
      final beforePinch=transform.value.storage[0];
      final center=tester.getCenter(find.byType(InteractiveViewer));
      final first=await tester.startGesture(center-const Offset(40,0),pointer:1);
      final second=await tester.startGesture(center+const Offset(40,0),pointer:2);
      await first.moveTo(center-const Offset(65,0));await second.moveTo(center+const Offset(65,0));await tester.pump();
      await first.moveTo(center-const Offset(90,0));await second.moveTo(center+const Offset(90,0));await tester.pump();
      await first.up();await second.up();await tester.pumpAndSettle();
      expect(transform.value.storage[0],isNot(beforePinch));
      expect(changed,0);
      await tester.pumpWidget(const SizedBox());await tester.pump();
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/calendar_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/thought_filters.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  testWidgets(
    'drop a thought on a date, set a start time and open its home schedule',
    (tester) async {
      elements.clear();
      final thought = elements.add('일정 테스트');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPage(
            selector: const SizedBox(),
            filters: ThoughtFilterSelection(),
            writable: true,
            changed: () => saves++,
          ),
        ),
      );
      final today = DateTime.now();
      final day = find.text('${today.day}');
      await tester.dragFrom(
        tester.getCenter(find.byType(Draggable<String>)),
        tester.getCenter(day) -
            tester.getCenter(find.byType(Draggable<String>)),
      );
      await tester.pumpAndSettle();
      expect(thought.calendar.values.single, isNull);
      await tester.tap(find.text('시간 미정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(thought.calendar.values.single, isA<int>());
      expect(saves, 2);
      WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).apply();
      expect(elements.byId(thought.id)!.calendar, thought.calendar);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HomeCalendar(open: () => opened = true)),
        ),
      );
      await tester.tap(find.text(thought.title));
      expect(opened, isTrue);
    },
  );
}

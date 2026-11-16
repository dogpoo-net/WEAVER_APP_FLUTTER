import 'package:weaver/features/inbox/word_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/workspace_events.dart';

class FakeEvents extends WorkspaceEvents {
 FakeEvents(void Function() change,void Function(bool) connection):super(onChange:change,onConnection:connection,open:(_)=>throw UnimplementedError());
 @override void resume(){onConnection(true);onChange();}
 @override void pause(){onConnection(false);}
 @override void dispose(){pause();}
}
void main(){
 testWidgets('push refreshes main and thought tab without idle polling; editing defers without losing event',(tester)async{
  SharedPreferences.setMockInitialValues({});elements.clear();memoBoxes.clear();
  elements.add('기존 메모');final initial=WorkspaceSnapshot.encode([]);
  elements.clear();elements.add('서버에서 변경됨');var remote=WorkspaceSnapshot.encode([]);elements.clear();
  final storage=WorkspaceStorage(await SharedPreferences.getInstance());await storage.write(initial);
  var checks=0,reads=0,dirty=false;late FakeEvents events;
  storage.checkRemote=()async{checks++;return dirty;};
  storage.refreshNow=()async{reads++;if(dirty){await storage.replaceFromBackup(remote);dirty=false;}};
  storage.watchRemote=(change,connection)=>events=FakeEvents(change,connection);
  await tester.pumpWidget(MaterialApp(navigatorObservers:[workspaceRouteObserver],home:InboxPage(storage:storage,themeMode:ThemeMode.light,onThemeChanged:(_){})));
  await tester.pumpAndSettle();await tester.pump(const Duration(milliseconds:250));await tester.pumpAndSettle();
  final baseline=checks;await tester.pump(const Duration(seconds:30));expect(checks,baseline);
  dirty=true;events.onChange();await tester.pump(const Duration(milliseconds:250));await tester.pumpAndSettle();
  expect(elements.records.containsKey('서버에서 변경됨'),true);expect(reads,1);
  await tester.tap(find.byKey(const ValueKey('thoughts-all')));await tester.pumpAndSettle();
  await tester.tap(find.text('생각').last);await tester.pumpAndSettle();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  remote=remote.replaceAll('서버에서 변경됨','생각 탭 변경');
  storage.editorResources.add('document');final before=checks;dirty=true;events.onChange();
  await tester.pump(const Duration(seconds:2));expect(checks,before);
  storage.editorResources.clear();await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();expect(checks,greaterThan(before));expect(dirty,false);expect(elements.records.containsKey('생각 탭 변경'),true);expect(find.byWidgetPredicate((w)=>w is WordBadge && w.word=='생각 탭 변경'),findsOneWidget);
  final after=checks;await tester.pump(const Duration(seconds:30));expect(checks,after);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(milliseconds:500));expect(checks,after);
  await tester.pumpWidget(const SizedBox());elements.clear();memoBoxes.clear();
 });
}

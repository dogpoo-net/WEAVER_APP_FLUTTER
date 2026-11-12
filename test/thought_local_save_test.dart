import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_routes.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main(){
 testWidgets('detail save immediately updates thought tab while server save remains pending without reread',(tester)async{
  elements.clear();elements.add('수정 전');
  var reads=0,saves=0;final pending=Completer<void>();
  refreshWorkspaceForRead=()async{reads++;};
  saveWorkspaceContent=(){saves++;return pending.future;};
  addTearDown((){refreshWorkspaceForRead=null;saveWorkspaceContent=null;elements.clear();});
  await tester.pumpWidget(const MaterialApp(home:ThoughtBoxView(notes:[])));
  await tester.tap(find.byType(WordBadge));await tester.pumpAndSettle();
  final before=reads;
  await tester.enterText(find.widgetWithText(TextField,'생각 내용'),'수정 후');
  await tester.tap(find.widgetWithText(FilledButton,'저장'));
  await tester.pump();await tester.pump(const Duration(milliseconds:300));
  expect(saves,1);expect(reads,before);expect(pending.isCompleted,false);
  expect(tester.widget<WordBadge>(find.byType(WordBadge)).word,'수정 후');
  expect(elements.records.containsKey('수정 후'),true);
  pending.complete();await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
 });
}

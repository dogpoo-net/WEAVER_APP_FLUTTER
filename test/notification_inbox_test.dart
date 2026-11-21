import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/notification_inbox.dart';
void main(){
 testWidgets('device recovery notification opens without writing a server notification',(tester)async{
  final actions=<String>[];
  Map<String,dynamic>? opened;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:NotificationBell(
    startupSyncPending:true,
    request:(action,_)async{actions.add(action);return {'unread':0,'items':[]};},
    onOpen:(item)async{opened=item;},
  ))));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('알림 · 읽지 않음 1개'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('동기화가 필요한 기기 자료가 있어요'));
  await tester.pumpAndSettle();
  expect(opened,{'kind':'startup-sync'});
  expect(actions, everyElement('notifications'));
  await tester.pumpWidget(const SizedBox());
 });

 testWidgets('unread badge, list and read all update without marking newer events',(tester)async{
  var unread=2;final writes=<Map<String,Object?>>[];
  Future<Map<String,dynamic>> request(String action,Map<String,Object?> body)async{
   if(action=='notifications/read'){writes.add(body);unread=0;return {};}
   return {'unread':unread,'items':body['countOnly']==true?[]:[{'id':12,'kind':'subscription','title':'구독 정보 변경','body':'Pro','createdAt':'2026-11-18T00:00:00Z','isRead':unread==0}]};
  }
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(actions:[NotificationBell(request:request)]))));await tester.pumpAndSettle();
  expect(tester.widget<Badge>(find.byKey(const ValueKey('notification-badge'))).isLabelVisible,isTrue);
  await tester.tap(find.byTooltip('알림 · 읽지 않음 2개'));await tester.pumpAndSettle();expect(find.text('구독 정보 변경'),findsOneWidget);
  await tester.tap(find.text('모두 읽음'));await tester.pumpAndSettle();expect(writes.single,{'id':12,'all':true});
  expect(tester.widget<Badge>(find.byKey(const ValueKey('notification-badge'))).isLabelVisible,isFalse);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('notification marks only its row and opens the related resource',(tester)async{
  Map<String,Object?>? marked;Map<String,dynamic>? opened;
  Future<Map<String,dynamic>> request(String action,Map<String,Object?> body)async{
   if(action=='notifications/read'){marked=body;return {};}
   return {'unread':1,'items':body['countOnly']==true?[]:[{'id':7,'kind':'comment','workspaceId':'space','targetId':'memo','title':'새 댓글','body':'메모에 새 댓글','createdAt':'2026-11-18T00:00:00Z','isRead':false}]};
  }
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:NotificationBell(request:request,onOpen:(item)async{opened=item;}))));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('알림 · 읽지 않음 1개'));await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('notification-7')));await tester.pumpAndSettle();
  expect(marked,{'id':7});expect(opened?['targetId'],'memo');expect(find.byType(AlertDialog),findsNothing);
  await tester.pumpWidget(const SizedBox());
 });
}

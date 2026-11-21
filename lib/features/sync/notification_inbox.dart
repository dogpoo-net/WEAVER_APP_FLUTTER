import 'dart:async';
import 'package:flutter/material.dart';
import '../inbox/memo_comments.dart' show commentAge;

typedef NotificationRequest = Future<Map<String,dynamic>> Function(String,Map<String,Object?>);
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key,required this.request,this.onOpen,this.startupSyncPending=false});
  final NotificationRequest request;
  final bool startupSyncPending;
  final Future<void> Function(Map<String,dynamic>)? onOpen;
  @override State<NotificationBell> createState()=>_NotificationBellState();
}
class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  Timer? timer;
  int unread=0;
  bool loading=false,active=true;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);refresh();timer=Timer.periodic(const Duration(seconds:60),(_)=>refresh());}
  @override void dispose(){timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){active=state==AppLifecycleState.resumed;if(active)refresh();}
  Future<void> refresh()async{
    if(loading||!active)return;loading=true;
    try{final data=await widget.request('notifications',{'countOnly':true});if(mounted)setState(()=>unread=(data['unread'] as num?)?.toInt()??0);}catch(_){/* Retry when active; the modal offers a visible error and retry. */}finally{loading=false;}
  }
  Future<void> open()async{
    final item=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>NotificationInbox(request:widget.request,startupSyncPending:widget.startupSyncPending,onUnread:(count){if(mounted)setState(()=>unread=count);}));
    if(item!=null&&mounted){try{await widget.onOpen?.call(item);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('알림을 열지 못했습니다. $e')));}}
    if(mounted)await refresh();
  }
  @override Widget build(BuildContext context) {
    final count=unread+(widget.startupSyncPending?1:0);
    return IconButton(tooltip:count>0?'알림 · 읽지 않음 $count개':'알림',onPressed:open,
      icon:Badge(key:const ValueKey('notification-badge'),isLabelVisible:count>0,label:Text(count>99?'99+':'$count'),child:const Icon(Icons.notifications_none)));
  }
}
class NotificationInbox extends StatefulWidget {
  const NotificationInbox({super.key,required this.request,required this.onUnread,this.startupSyncPending=false});
  final NotificationRequest request;
  final ValueChanged<int> onUnread;
  final bool startupSyncPending;
  @override State<NotificationInbox> createState()=>_NotificationInboxState();
}
class _NotificationInboxState extends State<NotificationInbox>{
  final items=<Map<String,dynamic>>[];
  bool loading=false,more=true;
  String? error;
  @override void initState(){super.initState();load();}
  Future<void> load({bool older=false})async{
    if(loading)return;setState((){loading=true;error=null;});
    try{
      final result=await widget.request('notifications',{if(older&&items.isNotEmpty)'before':items.last['id']});
      if(!mounted)return;
      final rows=(result['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
      setState((){if(!older)items.clear();items.addAll(rows);more=rows.length==50;});widget.onUnread((result['unread'] as num).toInt());
    }catch(e){if(mounted)setState(()=>error='알림을 불러오지 못했습니다. $e');}finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> readAll()async{
    if(loading||items.isEmpty)return;setState(()=>loading=true);
    try{await widget.request('notifications/read',{'id':items.first['id'],'all':true});if(mounted){setState(()=>loading=false);await load();}}
    catch(e){if(mounted)setState((){loading=false;error='읽음 처리하지 못했습니다. $e';});}
  }
  Future<void> open(Map<String,dynamic> item)async{
    if(loading)return;
    if(item['kind']=='invite'){
      final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('초대를 수락할까요?'),content:Text(item['body'] as String),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('수락'))]));
      if(yes!=true||!mounted)return;
    }
    setState(()=>loading=true);
    try{
      await widget.request('notifications/read',{'id':item['id']});
      if(item['kind']=='invite')await widget.request('accept',{'inviteId':item['targetId']});
      if(mounted)Navigator.pop(context,item);
    }catch(e){if(mounted)setState((){loading=false;error='알림을 열지 못했습니다. $e';});}
  }
  bool isRead(Map<String,dynamic> row)=>row['isRead']==true||row['isRead']==1;
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Row(children:[const Expanded(child:Text('알림')),TextButton(onPressed:loading||items.isEmpty?null:readAll,child:const Text('모두 읽음')),IconButton(tooltip:'닫기',onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))]),
    content:SizedBox(width:480,height:440,child:Column(children:[
      if(loading)const LinearProgressIndicator(),
      if(error!=null)...[Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),TextButton(onPressed:loading?null:load,child:const Text('다시 시도'))],
      if(widget.startupSyncPending)ListTile(
        leading:const Icon(Icons.sync_problem),
        title:const Text('동기화가 필요한 기기 자료가 있어요'),
        subtitle:const Text('서버 자료와 비교하고 남길 항목을 선택하세요.'),
        onTap:()=>Navigator.pop(context,<String,dynamic>{'kind':'startup-sync'}),
      ),
      Expanded(child:items.isEmpty?Center(child:Text(loading?'알림을 불러오는 중입니다.':'새 알림이 없습니다.')):
        ListView.separated(itemCount:items.length+(more?1:0),separatorBuilder:(_,i)=>const Divider(height:1),itemBuilder:(context,i){
          if(i==items.length)return TextButton(onPressed:loading?null:()=>load(older:true),child:const Text('이전 알림 더보기'));
          final row=items[i],read=isRead(row),date=DateTime.tryParse(row['createdAt'] as String? ?? '');
          return ListTile(key:ValueKey('notification-${row['id']}'),contentPadding:const EdgeInsets.symmetric(horizontal:4,vertical:4),
            leading:Badge(isLabelVisible:!read,child:Icon(switch(row['kind']){'invite'=>Icons.person_add_outlined,'comment'=>Icons.chat_bubble_outline,_=>Icons.workspace_premium_outlined})),
            title:Text(row['title'] as String,style:TextStyle(fontWeight:read?FontWeight.normal:FontWeight.bold)),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(row['body'] as String),if(date!=null)Text(commentAge(date,DateTime.now()),style:Theme.of(context).textTheme.labelSmall)]),onTap:loading?null:()=>open(row));
        })),
    ])),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/google_auth.dart';
import '../inbox/workspace_storage.dart';
import '../inbox/element_store.dart';
import '../inbox/word_badge.dart';
import 'owned_workspace.dart';

class OwnedWorkspaceGate extends StatefulWidget {
  const OwnedWorkspaceGate({super.key,required this.root,required this.auth,required this.builder});
  final WorkspaceStorage root;final GoogleAuthController auth;
  final Widget Function(WorkspaceStorage storage) builder;
  @override State<OwnedWorkspaceGate> createState()=>_OwnedWorkspaceGateState();
}
class _OwnedWorkspaceGateState extends State<OwnedWorkspaceGate> {
  WorkspaceStorage? storage;WorkspaceSync? sync;String? failure;int epoch=0;
  late final owner=widget.auth.isGuest?'guest':widget.auth.identity!.id;
  bool get current=>mounted && (widget.auth.isGuest?'guest':widget.auth.identity?.id)==owner;
  @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>open());}
  Future<void> open() async {
    try {
      final owned=OwnedWorkspaces(widget.root);await owned.initialize();if(!current)return;
      final target=owner=='guest'?await owned.guest():owned.scope(owner);
      if(owner!='guest'){
        final engine=WorkspaceSync(target,widget.auth.emailApi,isCurrent:()=>current);sync=engine;
        await engine.initialize();if(!current)return;
        if(!engine.ready && target.read()==null)throw StateError(engine.error??'서버 자료를 불러오지 못했습니다.');
        if(engine.ready){
          var claim=await owned.pendingClaim();
          if(claim==null){
            final guest=await owned.guest();final raw=guest.read();
            if(raw!=null){
              final snapshot=WorkspaceSnapshot.decode(raw);
              if(snapshot.records.isNotEmpty || snapshot.notes.isNotEmpty || snapshot.trashRecords.isNotEmpty){
                if(!current || !mounted)return;
                final yes=await showDialog<bool>(context:context,barrierDismissible:false,builder:(context)=>AlertDialog(
                  title:const Text('이 기기의 비회원 데이터를 가져올까요?'),
                  content:const Text('현재 계정에 업로드합니다. 완료된 자료는 비회원 공간에서 제거되며 다른 계정으로 다시 가져올 수 없습니다.'),
                  actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('나중에')),
                    FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('가져오기'))]));
                if(!current)return;
                if(yes==true)claim=await owned.sealGuest(owner,guest);
              }
            }
          }
          if(claim!=null && claim['account']==owner){
            try {await engine.importGuest(owned,claim);}catch(e){engine.error='가져오기를 완료하지 못했습니다. 이 계정에 보관된 비회원 자료로 다시 시도할 수 있습니다. $e';}
          }
        }
        engine.addListener(refresh);
        target.pullNow=()async{await engine.discardLocalAndPull();if(current){Navigator.of(context).popUntil((route)=>route.isFirst);setState(()=>epoch++);}};
        widget.auth.onSessionEnding=()async{await target.flush();await engine.removeCleanCache();};
      }
      if(!current)return;elements.clear();restoreWordColors({});setState((){storage=target;failure=null;});
    }catch(e){if(current)setState(()=>failure=e.toString());}
  }
  void refresh(){if(mounted)setState((){});}
  @override void dispose(){sync?.removeListener(refresh);sync?.dispose();storage?.suspended=true;widget.auth.onSessionEnding=null;super.dispose();}
  @override Widget build(BuildContext context){
    if(storage==null)return Scaffold(body:Center(child:failure==null?const CircularProgressIndicator():Column(mainAxisSize:MainAxisSize.min,children:[Text(failure!,textAlign:TextAlign.center),TextButton(onPressed:(){sync?.dispose();setState(()=>failure=null);unawaited(open());},child:const Text('다시 시도'))])));
    return Column(children:[
      if(sync?.error!=null) Material(color:Theme.of(context).colorScheme.errorContainer,child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[Expanded(child:Text('동기화되지 않은 자료는 이 계정에 보관됩니다. ${sync!.error}',maxLines:3)),TextButton(onPressed:sync!.busy?null:()=>sync!.flush().catchError((Object _) {}),child:const Text('재시도'))])))),
      Expanded(child:KeyedSubtree(key:ValueKey('$owner:$epoch'),child:widget.builder(storage!))),
    ]);
  }
}

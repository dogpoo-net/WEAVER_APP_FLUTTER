import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'workspace_storage.dart';

const takeoverMessage='현재 편집중입니다.\n잠금을 해제하면 문서를 편집할 수 있고, 저장 시 기존의 데이터는 저장한 데이터로 덮어씌워져요.\n정말 잠금을 해제하시겠어요?';
String wordWrapped(String text)=>text.splitMapJoin(RegExp(r'[^\s]+'),onMatch:(m)=>m[0]!.runes.map(String.fromCharCode).join('\u2060'));
class EditLock extends ChangeNotifier {
  EditLock(this.id,this.storage,{this.fallback,this.lazy=false}) {
    granted=callback==null;
    storage?.leaseChanges.addListener(_status);
    if(callback!=null){unawaited(lazy?observe():renew());_timer=Timer.periodic(const Duration(seconds:30),(_){if(WidgetsBinding.instance.lifecycleState==null || WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed)renew();});}
  }
  final String id;
  final bool lazy;
  bool held=false,shared=false;
  Future<bool>? _pending;
  final WorkspaceStorage? storage;
  final Future<Map<String,dynamic>> Function(String,String,bool)? fallback;
  Future<Map<String,dynamic>> Function(String,String,bool)? get callback=>storage?.documentLease??fallback;
  final token=List.generate(32,(_)=>Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();
  bool granted=false,busy=false,everGranted=false,_disposed=false;
  String? message;
  Timer? _timer;
  void _apply(Map<String,dynamic> result){
    if(_disposed)return;
    held=result['acquired']==true;shared=result['shared']==true;
    granted=held || (lazy && result['available']==true);
    everGranted=everGranted||granted;
    message=granted?null:'${result['holder']??'다른 화면'} 편집 중 · 읽기 전용';notifyListeners();
  }
  void _status(){final state=storage?.leaseStates[id];if(state!=null)_apply(state);}
  Future<bool> renew() => _request(lazy && !held ? 'observe' : 'renew');
  Future<bool> observe() => _request('observe');
  Future<bool> startEditing() => held && !busy ? Future.value(true) : _request('acquire');
  Future<bool> _request(String mode) {
    if(callback==null)return Future.value(true);
    final pending=_pending;
    if(pending!=null)return pending.then((_)=>_disposed?false:mode=='acquire'&&!held?_request(mode):granted);
    busy=true;
    return _pending=(() async {
      try {
        final result=mode=='observe' && storage?.inspectLease!=null ? await storage!.inspectLease!(id,token)
          :mode=='acquire' && storage?.acquireLease!=null ? await storage!.acquireLease!(id,token)
          :await callback!(id,token,false);
        _apply(result);
      }catch(_){if(!_disposed){granted=false;message='편집 권한을 확인하지 못했습니다. 작성 내용은 보관됩니다.';notifyListeners();}}
      finally{busy=false;}
      return granted;
    })().whenComplete(()=>_pending=null);
  }
  Future<void> saved() async {
    if(!lazy || callback==null)return;
    try { await callback!(id,token,true); } catch (_) { /* The save transaction already released the document lease. */ }
    held=false;
    if(!_disposed)await observe();
  }
  Future<void> takeOver(BuildContext context)async{
    if(busy || storage?.takeLease==null)return;
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(content:Text(wordWrapped(takeoverMessage),semanticsLabel:takeoverMessage,softWrap:true),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('잠금 해제'))]));
    if(yes!=true || _disposed)return;busy=true;
    try{_apply(await storage!.takeLease!(id,token));}
    catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('잠금을 변경하지 못했습니다. $e')));}
    finally{busy=false;}
  }
  @override void dispose(){_disposed=true;_timer?.cancel();storage?.leaseChanges.removeListener(_status);if(callback!=null)unawaited(callback!(id,token,true).then<void>((_){}).catchError((Object _){}));super.dispose();}
}
Future<bool> confirmReload(BuildContext context) async=>await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('서버 자료로 갱신할까요?'),content:const Text('이 화면의 저장하지 않은 변경을 서버에 저장된 데이터로 교체하고 편집 잠금을 확인합니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('갱신'))]))==true;

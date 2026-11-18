import 'dart:async';
import 'dart:convert';
import 'offline_workspace.dart';
import 'workspace_file_transfer.dart';

import 'package:flutter/material.dart';

import '../auth/google_auth.dart';
import '../auth/email_auth.dart';
import '../inbox/workspace_storage.dart';
import '../inbox/element_store.dart';
import '../inbox/word_badge.dart';
import '../inbox/workspace_routes.dart';
import '../capture/media_storage.dart';
import 'owned_workspace.dart';
import 'sharing_pages.dart';
import 'workspace_picker.dart';
import 'workspace_policy_page.dart';
import 'admin_backoffice_page.dart';
import 'readonly_workspace.dart';

class OwnedWorkspaceGate extends StatefulWidget {
  const OwnedWorkspaceGate({
    super.key,
    required this.root,
    required this.auth,
    required this.builder,
    this.inviteToken,
    this.onInviteHandled,
  });
  final WorkspaceStorage root;
  final GoogleAuthController auth;
  final String? inviteToken;
  final VoidCallback? onInviteHandled;
  final Widget Function(WorkspaceStorage storage) builder;
  @override
  State<OwnedWorkspaceGate> createState() => _OwnedWorkspaceGateState();
}

class _OwnedWorkspaceGateState extends State<OwnedWorkspaceGate> {
  WorkspaceStorage? storage;
  WorkspaceSync? sync;
  String? failure, notice;
  int epoch = 0, generation = 0;
  late final account = widget.auth.isGuest ? 'guest' : widget.auth.identity!.id;
  late final userId = account.startsWith('email:')
      ? account.substring(6)
      : account;
  String? selected, primaryWorkspace;
  String role = 'owner';
  List<dynamic> catalog = [];
  int invitations = 0;
  bool handledInvite = false, erasingAccount = false;
  bool emptyWorkspace=false,isAdmin=false,quotaReadOnly=false;
  List<dynamic> pendingInvites=[];
  bool get current =>
      mounted &&
      (widget.auth.isGuest ? 'guest' : widget.auth.identity?.id) == account;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  @override
  void didUpdateWidget(covariant OwnedWorkspaceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inviteToken != null && widget.inviteToken != oldWidget.inviteToken) {
      handledInvite = false;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) open(); });
    }
  }

  Future<void> open() async {
    final run = ++generation;
    bool valid() => current && run == generation && !erasingAccount;
    try {
      final owned = OwnedWorkspaces(widget.root);
      await owned.initialize();
      if (!valid()) return;
      WorkspaceStorage target;
      if (account == 'guest') {
        target = await owned.guest();
      } else {
        if (widget.inviteToken != null && !handledInvite) {
          handledInvite = true;
          if (!mounted) return;
          final accept = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('워크스페이스 초대를 수락할까요?'),
              content: const Text('초대받은 이메일로 로그인해야 합니다. 내 워크스페이스는 그대로 유지됩니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('나중에'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('수락'),
                ),
              ],
            ),
          );
          if (accept == true) {
            try {
              final result = await widget.auth.emailApi.workspace('accept', {
                'token': widget.inviteToken,
              });
              selected = result['workspaceId'] as String;
            } catch (e) {
              notice = e.toString();
            }
          }
          widget.onInviteHandled?.call();
        }
        Map<String,dynamic> list;
        final catalogKey='weaver.catalog.$account';
        try{list=await widget.auth.emailApi.workspace('catalog', {});await widget.root.preferences.setString(catalogKey,jsonEncode(list));}
        catch(e){if(e is EmailAuthFailure && (e.status==401 || e.status==403))rethrow;final cached=widget.root.preferences.getString(catalogKey);if(cached==null)rethrow;list=Map<String,dynamic>.from(jsonDecode(cached));list['workspaces']=(list['workspaces'] as List).where((r)=>r['role']=='owner'&&r['offline']==true).toList();if((list['workspaces'] as List).isEmpty)rethrow;}

        if (!valid()) return;
        catalog = list['workspaces'] as List;
        primaryWorkspace = list['defaultWorkspaceId'] as String?;
        isAdmin=list['isAdmin']==true;pendingInvites=list['invitations'] as List;
        if(!catalog.any((row)=>row['sharingSuspended']!=true)){
          sync?.removeListener(refresh);sync?.dispose();sync=null;storage?.suspended=true;MediaStorage.activeOwner=null;
          await widget.root.preferences.remove('weaver.selected-workspace.$account');
          if(valid())setState((){storage=null;selected=null;emptyWorkspace=true;failure=null;});
          return;
        }
        emptyWorkspace=false;
        invitations = (list['invitations'] as List).length;
        selected ??= widget.root.preferences.getString(
          'weaver.selected-workspace.$account',
        );
        if (!catalog.any((row) => row['workspaceId'] == selected && row['sharingSuspended']!=true)) {
          selected = list['defaultWorkspaceId'] as String? ?? catalog.firstWhere((row)=>row['sharingSuspended']!=true)['workspaceId'] as String;
        }
        role =
            catalog.firstWhere((row) => row['workspaceId'] == selected)['role']
                as String;
        final workspaceId = selected!;
        quotaReadOnly=catalog.firstWhere((row)=>row['workspaceId']==workspaceId)['quotaReadOnly']==true;
        target = owned.scope(
          workspaceId == userId ? account : '$account@workspace:$workspaceId',
        );
        target.currentUserId=userId;
        final row=catalog.firstWhere((row)=>row['workspaceId']==workspaceId);
        if(role=='owner'&&row['offline']==true){await openOffline(owned,target,workspaceId,valid);return;}

        final engine = WorkspaceSync(
          target,
          widget.auth.emailApi,
          workspaceId: workspaceId,
          readOnly: role == 'viewer'||quotaReadOnly,
          isCurrent: valid,
        );
        sync = engine;
        await engine.initialize();
        if (!valid()) return;
        if (!engine.ready && target.read() == null) {
          throw StateError(engine.error ?? '서버 자료를 불러오지 못했습니다.');
        }
        final offline=owned.scope(OfflineWorkspace.owner(account,workspaceId));
        if(engine.ready&&role=='owner'&&!quotaReadOnly&&OfflineWorkspace.hasChanges(offline)&&mounted){
          final publish=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('오프라인 작업을 서버에 반영할까요?'),content:const Text('이 기기에서 변경한 항목을 서버에 반영합니다. 같은 항목의 서버 내용은 오프라인 내용으로 교체될 수 있습니다. 나중에를 선택하면 오프라인 자료는 별도로 보관됩니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('나중에')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('반영'))]));
          if(publish==true){try{await OfflineWorkspace.publish(offline,engine);}catch(e){notice='오프라인 자료를 반영하지 못했습니다. 이 기기에 보관했습니다. $e';}}
        }
        if (engine.ready && workspaceId == primaryWorkspace && role=='owner' && !quotaReadOnly) {
          var claim = await owned.pendingClaim();
          if (claim == null) {
            final guest = await owned.guest();
            final raw = guest.read();
            if (raw != null) {
              final snapshot = WorkspaceSnapshot.decode(raw);
              if (snapshot.records.isNotEmpty ||
                  snapshot.notes.isNotEmpty ||
                  snapshot.trashRecords.isNotEmpty) {
                if (!valid() || !mounted) return;
                final yes = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('이 기기의 비회원 데이터를 가져올까요?'),
                    content: const Text(
                      '내 워크스페이스에 업로드합니다. 완료된 자료는 비회원 공간에서 제거되며 다른 계정으로 다시 가져올 수 없습니다.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('나중에'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('가져오기'),
                      ),
                    ],
                  ),
                );
                if (!valid()) return;
                if (yes == true) claim = await owned.sealGuest(account, guest);
              }
            }
          }
          if (claim != null && claim['account'] == account) {
            try {
              await engine.importGuest(owned, claim);
            } catch (e) {
              engine.error = '가져오기를 완료하지 못했습니다. 이 계정에서 다시 시도할 수 있도록 보관했습니다. $e';
            }
          }
        }
        target.workspaceName=catalog.firstWhere((row)=>row['workspaceId']==workspaceId)['name'] as String?;
        target.openWorkspaces=chooseWorkspace;
        target.openAdmin=isAdmin?openAdmin:null;
        if(role=='owner'&&!quotaReadOnly)attachFiles(target,engine);
        target.openPlan=()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>WorkspacePolicyPage(request:widget.auth.emailApi.workspace,workspaceId:workspaceId,owner:role=='owner'))).then((_)async{if(current)await switchWorkspace(workspaceId,force:true);});
        target.documentLease = engine.documentLease;
        engine.addListener(refresh);
        target.pullNow = () async {
          await engine.discardLocalAndPull();
          if (valid() && mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            setState(() => epoch++);
          }
        };
        target.openSharing = () => Navigator.of(context)
            .push<void>(
              MaterialPageRoute(
                builder: (_) => SharingPage(
                  sync: engine,
                  role: role,
                  onAccepted: (id)=>switchWorkspace(id,force:true),
                ),
              ),
            )
            .then((_) async {
              if (valid()) {
                final updated = await engine.request('catalog', {});
                if (valid()) {
                  setState(() {
                    catalog = updated['workspaces'] as List;
                    invitations = (updated['invitations'] as List).length;
                  });
                }
              }
            }).catchError((Object error) {
              if(valid())setState(()=>notice='초대 목록을 새로고침하지 못했습니다.');
            });
        target.openHistory = (id) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => DocumentHistoryPage(sync: engine, documentId: id),
          ),
        );
        final scopesKey = 'weaver.account.scopes.$account';
        final scopes = <String>{
          ...(widget.root.preferences.getStringList(scopesKey) ?? <String>[]),
          target.owner!,
        };
        await widget.root.preferences.setStringList(scopesKey, scopes.toList());
        widget.auth.onAccountErasureStarted=(){erasingAccount=true;target.suspended=true;};
        widget.auth.onAccountErasureFailed=(){erasingAccount=false;target.suspended=role=='viewer';};
        widget.auth.onSessionEnding = () async {
          await engine.settle();
          await target.flush();
          for (final owner
              in widget.root.preferences.getStringList(scopesKey) ?? []) {
            final local = owned.scope(owner);
            final cache = WorkspaceSync(
              local,
              widget.auth.emailApi,
              isCurrent: () => false,
            );
            try {
              cache.loadBase();
              await cache.removeCleanCache();
            } finally {
              cache.dispose();
            }
          }
        };
        await widget.root.preferences.setString(
          'weaver.selected-workspace.$account',
          workspaceId,
        );
        if (role == 'viewer') target.suspended = true;
      }
      if (!valid()) return;
      MediaStorage.activeOwner = target.owner;
      elements.clear();
      restoreWordColors({});
      setState(() {
        storage = target;
        failure = null;
      });
    } catch (e) {
      if (valid()) setState(() => failure = e.toString());
    }
  }

  String? _shownSyncError;
  bool _shownSyncBusy=false;
  void refresh() {
    final error=sync?.error,busy=sync?.busy??false;
    // The body does not depend on save progress. Rebuild only when the error
    // banner (or its retry button) actually changes.
    if(error==_shownSyncError&&(error==null||busy==_shownSyncBusy))return;
    _shownSyncError=error;_shownSyncBusy=busy;
    if (mounted) setState(() {});
  }

  Future<void> retry() async {
    try {
      final owned = OwnedWorkspaces(widget.root);
      final claim = await owned.pendingClaim();
      if (claim != null && claim['account'] == account && selected == primaryWorkspace) {
        await sync!.importGuest(owned, claim);
        if (current) setState(() => epoch++);
      } else {
        await sync!.flush();
      }
    } catch (e) {
      if (current) setState(() => sync!.error = e.toString());
    }
  }

  void attachFiles(WorkspaceStorage target,WorkspaceSync? engine){
    Future<void> guard()async{if(target.hasUnsavedInput?.call()==true)throw StateError('작성 중인 내용을 먼저 저장해주세요.');await engine?.settle();await target.flush();}
    target.exportFile=()async{await guard();await exportWorkspaceFile(target);};
    target.importFile=()async{await guard();if(!mounted)return;await importWorkspaceFile(context,target,sync:engine);if(current&&mounted){await navigateHome(context);if(mounted)setState(()=>epoch++);}};
  }
  Future<void> openOffline(OwnedWorkspaces owned,WorkspaceStorage source,String id,bool Function() valid)async{
    final local=owned.scope(OfflineWorkspace.owner(account,id));
    if(local.read()==null||!OfflineWorkspace.hasChanges(local)){
      if(source.read()==null){final reader=WorkspaceSync(source,widget.auth.emailApi,workspaceId:id,readOnly:true,isCurrent:valid);try{await reader.initialize();if(!reader.ready)throw StateError(reader.error??'서버 자료를 가져오지 못했습니다.');}finally{reader.dispose();}}
      await OfflineWorkspace.seed(local,source);
    }
    if(!valid())return;
    sync?.dispose();sync=null;local.currentUserId=userId;local.offlineMode=true;
    local.workspaceName=catalog.firstWhere((r)=>r['workspaceId']==id)['name'];
    local.openWorkspaces=chooseWorkspace;local.openAdmin=isAdmin?openAdmin:null;
    local.openPlan=()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>WorkspacePolicyPage(request:widget.auth.emailApi.workspace,workspaceId:id,owner:true))).then((_)async{if(current)await switchWorkspace(id,force:true);});
    if(!quotaReadOnly)attachFiles(local,null);
    local.suspended=quotaReadOnly;
    widget.auth.onSessionEnding=()async{await local.flush();};
    widget.auth.onAccountErasureStarted=(){erasingAccount=true;local.suspended=true;};
    widget.auth.onAccountErasureFailed=(){erasingAccount=false;local.suspended=quotaReadOnly;};
    final scopeKey='weaver.account.scopes.$account';await widget.root.preferences.setStringList(scopeKey,{...?widget.root.preferences.getStringList(scopeKey),local.owner!}.toList());
    await widget.root.preferences.setString('weaver.selected-workspace.$account',id);
    MediaStorage.activeOwner=local.owner;elements.clear();restoreWordColors({});
    if(valid())setState((){storage=local;failure=null;notice=null;});
  }

  Future<void> openAdmin()async{
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AdminBackofficePage(request:widget.auth.emailApi.workspace)));
    // Return to the same workspace and preserve its unsaved local state.
    if(current){final result=await widget.auth.emailApi.workspace('catalog',{});if(current)setState(()=>isAdmin=result['isAdmin']==true);storage?.openAdmin=isAdmin?openAdmin:null;}
  }
  Future<void> chooseWorkspace()async{
    try{final result=await widget.auth.emailApi.workspace('catalog',{});if(!current)return;catalog=result['workspaces'] as List;}catch(_){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('워크스페이스 목록을 불러오지 못했습니다.')));return;}
    if(!mounted)return;
    final id=await showDialog<String>(context:context,builder:(context)=>WorkspacePicker(
      workspaces:catalog,selected:selected,
      onManageMembers:(row)async{
        if(!current)return;
        final workspaceId=row['workspaceId'] as String;
        final temporary=sync==null;
        final engine=sync??WorkspaceSync(OwnedWorkspaces(widget.root).scope('$account@workspace:$workspaceId'),widget.auth.emailApi,workspaceId:workspaceId,readOnly:true,isCurrent:()=>current);
        try{
        await Navigator.of(this.context).push<void>(MaterialPageRoute(builder:(_)=>SharingPage(
          sync:engine,role:row['role'],workspaceId:workspaceId,
          requestOverride:(action,body)async{
            if(!current)throw StateError('계정이 변경되었습니다.');
            final result=await widget.auth.emailApi.workspace(action,{...body,'workspaceId':workspaceId});
            if(!current)throw StateError('계정이 변경되었습니다.');return result;
          },onAccepted:(id)=>switchWorkspace(id,force:true),
        )));
        }finally{if(temporary)engine.dispose();}
      },
      request:(action,body)async{
        if((action=='delete-workspace'||action=='leave-workspace')&&body['workspaceId']==selected){
          if(storage?.hasUnsavedInput?.call()==true)throw StateError('작성 중인 메모를 저장한 뒤 다시 시도해주세요.');
          await sync?.settle();await storage?.flush();
        }
        return widget.auth.emailApi.workspace(action,body);
      },
      onCatalog:(rows){
        if(!current)return;
        setState(()=>catalog=rows);
        final active=rows.where((row)=>row['workspaceId']==selected).firstOrNull;
        if(active!=null)storage?.workspaceName=active['name'] as String?;
      },
    ));
    if(current && (id!=null || !catalog.any((row)=>row['workspaceId']==selected)))await switchWorkspace(id, force:true,relinquished: !catalog.any((row)=>row['workspaceId']==selected));
  }

  Future<void> switchWorkspace(String? id,{bool force=false,bool relinquished=false}) async {
    if (!current || (!force && selected == id)) return;
    if (storage?.hasUnsavedInput?.call() == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('작성 중인 메모를 저장한 뒤 워크스페이스를 전환해주세요.')),
      );
      return;
    }
    final navigator=Navigator.of(context);
    await navigateHome(context);
    if(!mounted || navigator.canPop())return;
    try {
      if(!relinquished){await sync?.settle();}
      await storage?.flush();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('로컬 저장을 완료하지 못했습니다. $e')));
      }
      return;
    }
    generation++;
    sync?.removeListener(refresh);
    sync?.dispose();
    storage?.suspended = true;
    MediaStorage.activeOwner = null;
    if (!mounted) return;
    setState(() {
      selected = id;
      storage = null;
      failure = null;
    });
    await open();
  }

  @override
  void dispose() {
    generation++;
    sync?.removeListener(refresh);
    sync?.dispose();
    MediaStorage.activeOwner = null;
    storage?.suspended = true;
    widget.auth.onSessionEnding = null;
    widget.auth.onAccountErasureStarted=null;widget.auth.onAccountErasureFailed=null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if(emptyWorkspace && storage==null){return Scaffold(appBar:AppBar(title:const Text('워크스페이스'),actions:[if(isAdmin)IconButton(tooltip:'관리자 백오피스',onPressed:openAdmin,icon:const Icon(Icons.admin_panel_settings_outlined)),TextButton(onPressed:()=>widget.auth.signOut(),child:const Text('로그아웃'))]),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:480),child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(24),children:[const Text('이용 가능한 워크스페이스가 없습니다.',textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:chooseWorkspace,child:const Text('워크스페이스 선택 · 만들기 · 복원')),for(final invite in pendingInvites)ListTile(title:Text(invite['name']??'초대받은 워크스페이스'),trailing:TextButton(child:const Text('수락'),onPressed:()async{try{final result=await widget.auth.emailApi.workspace('accept',{'inviteId':invite['id']});if(current)await switchWorkspace(result['workspaceId'],force:true,relinquished:true);}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}))]))));}
    if (storage == null) {
      return Scaffold(
        body: Center(
          child: failure == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(failure!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () {
                        sync?.dispose();
                        setState(() => failure = null);
                        unawaited(open());
                      },
                      child: const Text('다시 시도'),
                    ),
                    TextButton(
                      onPressed: () => widget.auth.signOut(),
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
        ),
      );
    }
    return Column(
      children: [
        if (notice != null)
          Material(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(notice!),
            ),
          ),
        if (sync?.error != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '미동기화 자료는 이 계정에 보관됩니다. ${sync!.error}',
                        maxLines: 3,
                      ),
                    ),
                    TextButton(
                      onPressed: sync!.busy ? null : retry,
                      child: const Text('재시도'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('${storage!.owner}:$epoch'),
            child: (role == 'viewer'||quotaReadOnly) && account != 'guest'
                ? ReadonlyWorkspace(
                    storage: storage!,
                    onHistory: (id) => storage!.openHistory?.call(id),
                  )
                : widget.builder(storage!),
          ),
        ),
      ],
    );
  }
}

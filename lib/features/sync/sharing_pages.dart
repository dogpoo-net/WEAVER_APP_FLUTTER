import 'dart:async';
import 'document_revision_diff.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'owned_workspace.dart';

String roleLabel(String role) => switch (role) {
  'owner' => '소유자',
  'editor' => '편집자',
  _ => '읽기 전용',
};

class SharingPage extends StatefulWidget {
  const SharingPage({
    super.key,
    required this.sync,
    required this.role,
    required this.onAccepted,
    this.workspaceId, this.requestOverride,
  });
  final String? workspaceId;
  final Future<Map<String,dynamic>> Function(String,Map<String,Object?>)? requestOverride;
  final WorkspaceSync sync;
  final String role;
  final Future<void> Function(String) onAccepted;
  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  String? get workspaceId => widget.workspaceId ?? widget.sync.workspaceId;
  Future<Map<String,dynamic>> request(String action,Map<String,Object?> body) => (widget.requestOverride ?? widget.sync.request)(action,body);
  bool busy = false;
  String? error, link, message;
  String? workspaceName;
  String plan = 'Free';
  bool loaded = false;
  List<dynamic> members = [], invitations = [], received = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final data = await request('members', {});
    final catalog = await request('catalog', {});
    if (mounted) {
      setState(() {
        final workspace = (catalog['workspaces'] as List).where((item) => item['workspaceId'] == workspaceId).firstOrNull;
        workspaceName = workspace?['name'] as String? ?? widget.sync.storage.workspaceName ?? '워크스페이스';
        plan = switch ((workspace?['plan'] ?? 'free').toString().toLowerCase()) { 'standard' => 'Standard', 'pro' => 'Pro', _ => 'Free' };
        loaded = true;
        members = data['members'] as List;
        invitations = data['invitations'] as List;
        received = catalog['invitations'] as List;
      });
    }
  }

  Widget memberTile(Map person) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(person['name'] ?? person['email']),
            subtitle: Text('${person['email']} · ${roleLabel(person['role'])}'),
            trailing: widget.role == 'owner' && person['role'] != 'owner'
                ? PopupMenuButton<String>(
                    enabled: !busy,
                    onSelected: (action) => run(() async {
                      if(action=='transfer'){
                        final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('소유권을 이전할까요?'),content:Text('${person['name']??person['email']}님이 소유자가 되며, 나는 편집자로 남습니다. 이 작업을 임의로 되돌릴 수 없습니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('이전'))]));
                        if(yes!=true)return;
                        await request('transfer',{'userId':person['userId']});
                        if(mounted)Navigator.pop(context);
                        await widget.onAccepted(workspaceId!);
                        return;
                      }
                      await request(
                        action == 'remove' ? 'remove-member' : 'member-role',
                        {
                          'userId': person['userId'],
                          if (action != 'remove') 'role': action,
                        },
                      );
                      await refresh();
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'editor', child: Text('편집자로 변경')),
                      PopupMenuItem(value: 'viewer', child: Text('읽기 전용으로 변경')),
                      PopupMenuItem(value: 'remove', child: Text('참여자 제거')),
                      PopupMenuItem(value: 'transfer', child: Text('소유권 이전')),
                    ],
                  )
                : null,
          );

  Future<void> load() => run(refresh);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('멤버 관리'), actions: [
      IconButton(tooltip: '참여 안내', icon: const Icon(Icons.info_outline),
        onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('참여 안내'),
          content: const Text('읽기 전용 참여자는 인원제한 없이 참여할 수 있습니다.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
        ))),
    ]),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Text(loaded ? '$plan / $workspaceName / ${members.length}명' : '워크스페이스 정보를 불러오는 중…',
          key: const ValueKey('workspace-member-summary'), style: Theme.of(context).textTheme.bodySmall),
        const Divider(),
        Row(children: [
          Text('참여자', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          if (widget.role == 'owner') FilledButton.icon(
            style: FilledButton.styleFrom(textStyle: Theme.of(context).textTheme.bodyMedium,
              minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: busy ? null : () async {
              final result = await showDialog<Map<String,dynamic>>(context: context,
                builder: (_) => _InviteDialog(request: request));
              if (!mounted || result == null) return;
              setState(() {
                link = 'https://weaver.dogpoo.net/#invite=${result['token']}';
                message = result['mailSent'] == true
                  ? '초대 메일을 보냈습니다. 초대는 7일 동안 유효합니다.'
                  : '메일 전송에 실패했습니다. 아래 초대 링크를 전달할 수 있습니다.';
              });
              await load();
            }, icon: const Icon(Icons.person_add_outlined, size: 16), label: const Text('초대하기')),
        ]),
        if (widget.role == 'owner') ...[
          if (message != null) Text(message!),
          if (link != null)
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: link!)),
              child: const Text('초대 링크 복사'),
            ),
        ],
        for (final person in members.where((person) => person['role'] != 'viewer')) memberTile(person as Map),
        if (members.any((person) => person['role'] == 'viewer')) ...[
          if (members.any((person) => person['role'] != 'viewer')) const Divider(),
          for (final person in members.where((person) => person['role'] == 'viewer')) memberTile(person as Map),
        ],
        if (invitations.isNotEmpty) ...[
          const Divider(),
          const Text('보낸 초대 · 수락 대기'),
        ],
        for (final invite in invitations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(invite['email']),
            subtitle: Text(roleLabel(invite['role'])),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await request('revoke', {
                        'inviteId': invite['id'],
                      });
                      await refresh();
                    }),
              child: const Text('초대 취소'),
            ),
          ),
        if (received.isNotEmpty) ...[const Divider(), const Text('받은 초대')],
        for (final invite in received)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(invite['name'] ?? '내 워크스페이스'),
            subtitle: Text(roleLabel(invite['role'])),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final result = await request('accept', {
                        'inviteId': invite['id'],
                      });
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await widget.onAccepted(result['workspaceId'] as String);
                    }),
              child: const Text('수락'),
            ),
          ),
      ],
    ),
  );
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.request});
  final Future<Map<String,dynamic>> Function(String,Map<String,Object?>) request;
  @override
  State<_InviteDialog> createState()=>_InviteDialogState();
}
class _InviteDialogState extends State<_InviteDialog> {
  final email=TextEditingController();
  final emailFocus=FocusNode();
  Timer? searchTimer;
  int searchVersion=0;
  int selected=-1;
  List<String> suggestions=[];
  void search(String value){
    searchTimer?.cancel();
    final version=++searchVersion;
    setState((){suggestions=[];selected=-1;error=null;});
    if(value.trim().length<2)return;
    searchTimer=Timer(const Duration(milliseconds:250),()async{
      try{
        final result=await widget.request('invite-emails',{'email':value.trim()});
        if(!mounted || version!=searchVersion)return;
        setState(()=>suggestions=List<String>.from(result['emails'] as List));
      }catch(e){if(mounted && version==searchVersion)setState(()=>error='이메일 검색을 완료하지 못했습니다. 다시 입력해주세요.');}
    });
  }
  void choose(String value){
    searchTimer?.cancel();searchVersion++;
    email.value=TextEditingValue(text:value,selection:TextSelection.collapsed(offset:value.length));
    setState((){suggestions=[];selected=-1;error=null;});
    emailFocus.requestFocus();
  }
  KeyEventResult onEmailKey(FocusNode node,KeyEvent event){
    if(busy || event is! KeyDownEvent || suggestions.isEmpty)return KeyEventResult.ignored;
    if(event.logicalKey==LogicalKeyboardKey.arrowDown){
      setState(()=>selected=(selected+1)%suggestions.length);return KeyEventResult.handled;
    }
    if(event.logicalKey==LogicalKeyboardKey.arrowUp){
      setState(()=>selected=selected<=0?suggestions.length-1:selected-1);return KeyEventResult.handled;
    }
    if(event.logicalKey==LogicalKeyboardKey.enter && selected>=0){choose(suggestions[selected]);return KeyEventResult.handled;}
    if(event.logicalKey==LogicalKeyboardKey.escape){setState((){suggestions=[];selected=-1;});return KeyEventResult.handled;}
    return KeyEventResult.ignored;
  }
  String role='editor';
  bool busy=false;
  String? error;
  @override
  void dispose(){searchTimer?.cancel();emailFocus.dispose();email.dispose();super.dispose();}
  Future<void> send()async{
    if(busy)return;
    if(email.text.trim().isEmpty){setState(()=>error='초대할 이메일을 입력해주세요.');return;}
    setState((){busy=true;error=null;});
    try{
      final result=await widget.request('invite',{'email':email.text.trim(),'role':role});
      if(mounted)Navigator.pop(context,result);
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:const Text('초대하기'),
    content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Focus(onKeyEvent:onEmailKey,child:TextField(controller:email,focusNode:emailFocus,autofocus:true,enabled:!busy,keyboardType:TextInputType.emailAddress,
        onChanged:search,decoration:const InputDecoration(labelText:'초대할 이메일',helperText:'이메일을 두 글자 이상 입력해주세요.'),onSubmitted:(_)=>send())),
      for(var i=0;i<suggestions.length;i++)
        ListTile(dense:true,selected:i==selected,selectedTileColor:Theme.of(context).colorScheme.secondaryContainer,
          title:Text(suggestions[i]),onTap:busy?null:()=>choose(suggestions[i])),
      const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:role,decoration:const InputDecoration(labelText:'멤버 타입'),
        onChanged:busy?null:(value)=>setState(()=>role=value!),items:const[
          DropdownMenuItem(value:'editor',child:Text('편집자')),
          DropdownMenuItem(value:'viewer',child:Text('읽기 전용')),
        ]),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(busy)const LinearProgressIndicator(),
    ]))),
    actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('취소')),
      FilledButton(onPressed:busy?null:send,child:Text(busy?'전송 중…':'초대메일 보내기'))],
  ));
}

class DocumentHistoryPage extends StatefulWidget {
  const DocumentHistoryPage({
    super.key,
    required this.sync,
    required this.documentId,
  });
  final WorkspaceSync sync;
  final String documentId;
  @override
  State<DocumentHistoryPage> createState() => _DocumentHistoryPageState();
}

class _DocumentHistoryPageState extends State<DocumentHistoryPage> {
  final versions = <dynamic>[];
  Timer? _refreshTimer;
  bool _refreshing = false;
  @override void dispose() { _refreshTimer?.cancel(); super.dispose(); }
  Future<void> refreshLatest() async {
    final lifecycle=WidgetsBinding.instance.lifecycleState;
    if(!mounted || busy || _refreshing || ModalRoute.of(context)?.isCurrent!=true || (lifecycle!=null && lifecycle!=AppLifecycleState.resumed))return;
    _refreshing=true;
    try {
      final result=await widget.sync.request('history',{'documentId':widget.documentId});
      if(!mounted)return;
      final rows=result['versions'] as List;
      if(rows.isNotEmpty && versions.isNotEmpty && rows.first['version']==versions.first['version'])return;
      setState(() {
        final overlap=rows.isNotEmpty && versions.any((v)=>v['version']==rows.last['version']);
        final older=overlap?versions.where((v)=>(v['version'] as num)<(rows.last['version'] as num)).toList():<dynamic>[];
        versions..clear()..addAll(rows)..addAll(older);
        if(!overlap)more=rows.length==50;
        error=null;
      });
    } catch (_) { /* Keep the existing history while a transient request fails. */ }
    finally {_refreshing=false;}
  }
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    _refreshTimer=Timer.periodic(const Duration(seconds:3),(_)=>refreshLatest());
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.sync.request('history', {
        'documentId': widget.documentId,
        if (versions.isNotEmpty) 'beforeVersion': versions.last['version'],
      });
      final rows = result['versions'] as List;
      if (mounted) {
        setState(() {
          versions.addAll(rows);
          more = rows.length == 50;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String timestamp(dynamic value) {
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toLocal().toString().split('.').first ?? value.toString();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('문서 변경 이력')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('저장된 본문 버전입니다. 추가·삭제 수는 서식 문법과 공백을 포함한 Unicode 글자 수입니다.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!busy && versions.isEmpty && error == null)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('저장된 변경 이력이 없습니다.'),
          ),
        for (final version in versions)
          ExpansionTile(key: ValueKey('document-history-${version['version']}'),
            title: Row(children: [Expanded(child: Text('버전 ${version['version']} · ${version['actorName']}')),
              if (version['action'] == 'unlocked_edit') const Tooltip(message: '이 버전은 잠금 해제 후 저장했습니다.', child: Icon(Icons.lock_open, size: 18))]),
            subtitle: Text(
              '${timestamp(version['createdAt'])}\n+${version['added']}자 / −${version['removed']}자 · 순변화 ${(version['added'] as num) - (version['removed'] as num)}자',
            ),
            children: [
              for (final chunk
                  in jsonDecode(version['changes'] as String) as List)
                if (chunk['operation'] != 'equal')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: chunk['operation'] == 'insert'
                          ? Colors.green.withValues(alpha: .14)
                          : Colors.red.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${chunk['operation'] == 'insert' ? '추가' : '삭제'} · ${chunk['operation'] == 'insert' ? chunk['afterLine'] : chunk['beforeLine']}행부터',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SelectableText(chunk['text'] as String),
                      ],
                    ),
                  ),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    title: Text('버전 ${version['version']} 전체 변경 비교'),
                    content: SizedBox(width: MediaQuery.sizeOf(context).width,
                      height: MediaQuery.sizeOf(context).height * .72,
                      child: DocumentRevisionDiff(chunks: jsonDecode(version['changes'] as String) as List)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('닫기'),
                      ),
                    ],
                  ),
                ),
                child: const Text('이 버전 전체 보기'),
              )),
            ],
          ),
        if (more)
          TextButton(
            onPressed: busy ? null : load,
            child: Text(error == null ? '이전 버전 더 보기' : '다시 시도'),
          ),
      ],
    ),
  );
}

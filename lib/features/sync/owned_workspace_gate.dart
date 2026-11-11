import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/google_auth.dart';
import '../inbox/workspace_storage.dart';
import '../inbox/element_store.dart';
import '../inbox/word_badge.dart';
import '../capture/media_storage.dart';
import 'owned_workspace.dart';
import 'sharing_pages.dart';
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
  String? selected;
  String role = 'owner';
  List<dynamic> catalog = [];
  int invitations = 0;
  bool handledInvite = false;
  bool get current =>
      mounted &&
      (widget.auth.isGuest ? 'guest' : widget.auth.identity?.id) == account;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  Future<void> open() async {
    final run = ++generation;
    bool valid() => current && run == generation;
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
        final list = await widget.auth.emailApi.workspace('catalog', {});
        if (!valid()) return;
        catalog = list['workspaces'] as List;
        invitations = (list['invitations'] as List).length;
        selected ??= widget.root.preferences.getString(
          'weaver.selected-workspace.$account',
        );
        if (!catalog.any((row) => row['workspaceId'] == selected)) {
          selected = userId;
        }
        role =
            catalog.firstWhere((row) => row['workspaceId'] == selected)['role']
                as String;
        final workspaceId = selected!;
        target = owned.scope(
          workspaceId == userId ? account : '$account@workspace:$workspaceId',
        );
        final engine = WorkspaceSync(
          target,
          widget.auth.emailApi,
          workspaceId: workspaceId,
          readOnly: role == 'viewer',
          isCurrent: valid,
        );
        sync = engine;
        await engine.initialize();
        if (!valid()) return;
        if (!engine.ready && target.read() == null) {
          throw StateError(engine.error ?? '서버 자료를 불러오지 못했습니다.');
        }
        if (engine.ready && workspaceId == userId) {
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
                  onAccepted: switchWorkspace,
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

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> retry() async {
    try {
      final owned = OwnedWorkspaces(widget.root);
      final claim = await owned.pendingClaim();
      if (claim != null && claim['account'] == account && selected == userId) {
        await sync!.importGuest(owned, claim);
        if (current) setState(() => epoch++);
      } else {
        await sync!.flush();
      }
    } catch (e) {
      if (current) setState(() => sync!.error = e.toString());
    }
  }

  Future<void> switchWorkspace(String id) async {
    if (!current || selected == id) return;
    if (storage?.hasUnsavedInput?.call() == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('작성 중인 메모를 저장한 뒤 워크스페이스를 전환해주세요.')),
      );
      return;
    }
    try {
      await sync?.settle();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        if (account != 'guest')
          Material(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selected,
                        onChanged: (id) {
                          if (id != null) unawaited(switchWorkspace(id));
                        },
                        items: [
                          for (final item in catalog)
                            DropdownMenuItem(
                              value: item['workspaceId'] as String,
                              child: Text(
                                '${item['name'] ?? '공유'}${item['role'] == 'owner' ? '' : '의 워크스페이스'} · ${roleLabel(item['role'])}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: invitations > 0
                          ? '받은 초대 $invitations개'
                          : '초대·참여자',
                      icon: Badge(
                        isLabelVisible: invitations > 0,
                        label: Text('$invitations'),
                        child: const Icon(Icons.group_add_outlined),
                      ),
                      onPressed: storage!.openSharing,
                    ),
                    if (role == 'viewer')
                      IconButton(
                        tooltip: '로그아웃',
                        onPressed: () => widget.auth.signOut(),
                        icon: const Icon(Icons.logout),
                      ),
                  ],
                ),
              ),
            ),
          ),
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
            child: role == 'viewer' && account != 'guest'
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

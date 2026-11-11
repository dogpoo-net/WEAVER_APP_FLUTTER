import '../sync/workspace_backup.dart';
import '../auth/google_auth.dart';
import '../auth/email_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'element_store.dart';
import 'word_badge.dart';

const closedThoughtsPreference = 'weaver.showClosedThoughts.v1';
bool showClosedThoughts = true;
bool canBrowseThought(ElementRecord record) => showClosedThoughts || !record.hiddenFromSearch;

Future<void> showThoughtSettings(BuildContext context, SharedPreferences? preferences, {
  Future<void> Function()? onUpload,
  Future<void> Function()? onDownload,
  Future<void> Function()? onReset,
  Future<void> Function()? onSignIn,
}) async {
  var busy = false;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
    Future<void> run(Future<void> Function() action) async {
      if (busy) return;
      update(() => busy = true);
      try { await action(); }
      catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            error is BackupFailure ? error.message : error is EmailAuthFailure ? error.message : '데이터 작업을 완료하지 못했습니다. 현재 데이터를 확인하고 다시 시도해주세요.')));
        }
      } finally { if (context.mounted) update(() => busy = false); }
    }
    Future<void> changeVisibility(bool value) async {
      if (busy) return;
            try {
              if (preferences != null && !await preferences.setBool(closedThoughtsPreference, value)) throw StateError('Settings save failed');
              showClosedThoughts = value; elements.refreshVisibility();
              if (context.mounted) update(() {});
            } catch (_) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('환경설정을 저장하지 못했습니다.')));
            }
    }
    final auth = GoogleAuthScope.maybeOf(context);
    final signedIn = auth?.identity != null;
    final cloudEnabled = auth?.canUseCloud ?? false;
    final guest = auth?.isGuest ?? false;
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final settings = ListTileTheme(
      data: ListTileThemeData(dense: true, minLeadingWidth: 20, horizontalTitleGap: 8,
      minVerticalPadding: 0, visualDensity: VisualDensity.compact,
      titleTextStyle: Theme.of(context).textTheme.bodySmall,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant),
      child: IconTheme(data: const IconThemeData(size: 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (signedIn) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline),
          title: Text(auth!.identity!.displayName?.trim().isNotEmpty == true ? auth.identity!.displayName! : '내 계정'),
          subtitle: Text(auth.identity!.email)),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('닫힌 생각 숨기기'),
          onTap: busy ? null : () => changeVisibility(!showClosedThoughts),
          trailing: SizedBox(width: 44, height: 36, child: Transform.scale(scale: .75, child: Switch(value: !showClosedThoughts,
          onChanged: busy ? null : (hidden) => changeVisibility(!hidden))))),
        const Divider(),
        if (guest) const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline),
          title: Text('비회원 · 로컬 저장 전용'), subtitle: Text('클라우드 저장·가져오기는 로그인 후 사용할 수 있습니다. 저장한 로컬 데이터는 로그인 후에도 유지됩니다.')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.cloud_upload_outlined), title: const Text('데이터 저장하기'), enabled: cloudEnabled && !busy,
          onTap: busy || !cloudEnabled || onUpload == null ? null : () => run(onUpload)),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.cloud_download_outlined), title: const Text('데이터 가져오기'), enabled: cloudEnabled && !busy,
          onTap: busy || !cloudEnabled || onDownload == null ? null : () => run(onDownload)),
        if (busy) const LinearProgressIndicator(),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline), title: const Text('데이터 초기화'),
          onTap: busy || onReset == null ? null : () { Navigator.pop(dialogContext); onReset(); }),
        const Divider(),
        if (guest) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.login), title: const Text('로그인 / 회원가입'),
          onTap: busy ? null : () => run(onSignIn ?? auth!.leaveGuest))
        else ListTile(contentPadding: EdgeInsets.zero, title: const Text('로그아웃', style: TextStyle(color: Color(0xFFD64550))),
          onTap: busy || !signedIn ? null : () => run(() async {
            await auth!.signOut();
            if (auth.error != null) throw BackupFailure(auth.error!);
          })),
        const Divider(),
        if (auth?.isEmailAccount == true && auth!.kakaoClient.configured) ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('카카오 계정 연결'), onTap: busy ? null : () => run(() async {
            final linked = await auth.linkKakao();
            if (linked && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('카카오 계정을 연결했습니다.')));
          })),
        if (auth?.isEmailAccount == true) ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('네이버 계정 연결'), onTap: busy ? null : () => run(() async {
            final linked = await auth!.linkBrowser('naver');
            if (linked && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('네이버 계정을 연결했습니다.')));
          })),
        if (auth?.isEmailAccount == true) ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('GitHub 계정 연결'), onTap: busy ? null : () => run(() async {
            final linked = await auth!.linkBrowser('github');
            if (linked && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitHub 계정을 연결했습니다.')));
          })),
        if (auth?.isEmailAccount == true) ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('GitLab 계정 연결'), onTap: busy ? null : () => run(() async {
            final linked = await auth!.linkBrowser('gitlab');
            if (linked && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GitLab 계정을 연결했습니다.')));
          })),
        if (auth?.isEmailAccount == true) ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('모든 기기에서 로그아웃'), onTap: busy ? null : () => run(() async {
            final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
              title: const Text('모든 기기에서 로그아웃할까요?'),
              content: const Text('현재 계정의 모든 기기 세션을 폐기합니다. 저장한 로컬 데이터는 유지됩니다.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('전체 로그아웃'))]));
            if (confirmed == true) {
              await auth!.signOut(allDevices: true);
              if (auth.error != null) throw BackupFailure(auth.error!);
            }
          })),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('오픈소스 사용 정보'), trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : () => showLicensePage(context: context, applicationName: 'WEAVER')),
      ])));
    final close = TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('닫기'));
    return PopScope(canPop: !busy, child: mobile ? Dialog(
      alignment: AlignmentDirectional.topStart,
      insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 12),
      child: SizedBox(width: double.infinity, height: double.infinity, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('환경설정', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: settings)),
          Align(alignment: Alignment.centerRight, child: close),
        ]),
      )),
    ) : AlertDialog(
      title: const Text('환경설정'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: settings)),
      actions: [close],
    ));
  }));
}

Future<void> showClosedThoughtsDialog(BuildContext context) => showDialog<void>(context: context,
  builder: (context) => AlertDialog(title: const Text('닫힌 생각'),
    content: SizedBox(width: 520, height: 400, child: ListenableBuilder(listenable: elements, builder: (context, _) {
      final records = elements.records.values.where((r) => r.hiddenFromSearch).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (records.isEmpty) return const Center(child: Text('닫힌 생각이 없습니다.'));
      return ListView.separated(itemCount: records.length, separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => WordBadge(word: records[index].text, fullText: true,
          onTap: () => showElementMetadata(context, records[index].text)));
    })), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))]));

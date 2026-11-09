import '../sync/workspace_backup.dart';
import '../auth/google_auth.dart';
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
}) async {
  var busy = false;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
    Future<void> run(Future<void> Function() action) async {
      if (busy) return;
      update(() => busy = true);
      try { await action(); }
      catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is BackupFailure ? error.message : '데이터 작업을 완료하지 못했습니다. 현재 데이터를 확인하고 다시 시도해주세요.')));
      } finally { if (context.mounted) update(() => busy = false); }
    }
    final auth = GoogleAuthScope.maybeOf(context);
    final signedIn = auth?.identity != null;
    return PopScope(canPop: !busy, child: AlertDialog(
      title: const Text('환경설정'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('닫힌 생각 조회'), value: showClosedThoughts,
          onChanged: busy ? null : (value) async {
            try {
              if (preferences != null && !await preferences.setBool(closedThoughtsPreference, value)) throw StateError('Settings save failed');
              showClosedThoughts = value; elements.refreshVisibility();
              if (context.mounted) update(() {});
            } catch (_) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('환경설정을 저장하지 못했습니다.')));
            }
          }),
        const Divider(),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.cloud_upload_outlined), title: const Text('데이터 저장하기'),
          onTap: busy || !signedIn || onUpload == null ? null : () => run(onUpload)),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.cloud_download_outlined), title: const Text('데이터 가져오기'),
          onTap: busy || !signedIn || onDownload == null ? null : () => run(onDownload)),
        if (busy) const LinearProgressIndicator(),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline), title: const Text('데이터 초기화'),
          onTap: busy || onReset == null ? null : () { Navigator.pop(dialogContext); onReset(); }),
        const Divider(),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('로그아웃', style: TextStyle(color: Color(0xFFD64550))),
          onTap: busy || !signedIn ? null : () => run(() async {
            await auth!.signOut();
            if (auth.error != null) throw BackupFailure(auth.error!);
          })),
        const Divider(),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('오픈소스 사용 정보'), trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : () => showLicensePage(context: context, applicationName: 'WEAVER')),
      ]))),
      actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('닫기'))],
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

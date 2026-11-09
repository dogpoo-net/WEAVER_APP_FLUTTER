import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'element_store.dart';
import 'word_badge.dart';

const closedThoughtsPreference = 'weaver.showClosedThoughts.v1';
bool showClosedThoughts = true;
bool canBrowseThought(ElementRecord record) => showClosedThoughts || !record.hiddenFromSearch;

Future<void> showThoughtSettings(BuildContext context, SharedPreferences? preferences) => showDialog<void>(
  context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
    title: const Text('환경설정'),
    content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('닫힌 생각 조회'), value: showClosedThoughts,
        onChanged: (value) async {
          try {
            if (preferences != null && !await preferences.setBool(closedThoughtsPreference, value)) throw StateError('Settings save failed');
            showClosedThoughts = value;
            elements.refreshVisibility();
            if (context.mounted) update(() {});
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('환경설정을 저장하지 못했습니다.')));
          }
        }),
      const ListTile(contentPadding: EdgeInsets.zero, title: Text('로그아웃', style: TextStyle(color: Color(0xFFD64550)))),
      const Divider(),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('오픈소스 사용 정보'), trailing: const Icon(Icons.chevron_right),
        onTap: () => showLicensePage(context: context, applicationName: 'WEAVER')),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
  )));

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

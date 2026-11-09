import 'package:flutter/material.dart';
import 'desktop_menu_frame.dart';
import 'element_store.dart';
import 'word_badge.dart';
import 'workspace_routes.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.onDelete});
  final Future<void> Function(String id) onDelete;
  @override
  State<TrashPage> createState() => _TrashPageState();
}
class _TrashPageState extends State<TrashPage> {
  String _query = '';
  bool _emptying = false;
  Future<void> _emptyTrash() async {
    if (_emptying || elements.trash.isEmpty) return;
    final ids = elements.trash.keys.toList();
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('휴지통을 비울까요?'),
      content: Text('검색 결과와 관계없이 휴지통의 생각 ${ids.length}개와 첨부파일을 영구 삭제합니다. 서버 백업은 유지됩니다.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('모두 삭제'))]));
    if (yes != true || !mounted) return;
    setState(() => _emptying = true);
    final delete = widget.onDelete;
    try {
      for (final id in ids) { await delete(id); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('휴지통을 비웠습니다.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('일부 항목을 삭제하지 못했습니다. 남은 항목을 다시 삭제해주세요.')));
    } finally { if (mounted) setState(() => _emptying = false); }
  }
  Future<void> _open(ElementRecord record) async {
    if (_emptying) return;
    var busy = false;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => PopScope(canPop: !busy, child: AlertDialog(
        title: const Text('휴지통의 생각'),
        content: SingleChildScrollView(child: Text(record.text)),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('닫기')),
          TextButton(onPressed: busy ? null : () async {
            final yes = await showDialog<bool>(context: dialogContext, builder: (context) => AlertDialog(
              title: const Text('완전히 삭제할까요?'),
              content: const Text('이 기기의 생각과 첨부파일을 삭제합니다. 되돌릴 수 없습니다. 서버에 저장한 백업은 별도로 유지됩니다.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('영구 삭제'))]));
            if (yes != true || !dialogContext.mounted) return;
            update(() => busy = true);
            try {
              await widget.onDelete(record.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) setState(() {});
            } catch (_) {
              if (dialogContext.mounted) {
                update(() => busy = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('완전 삭제를 저장하지 못했습니다. 다시 시도해주세요.')));
              }
            }
          }, child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('영구 삭제')),
        ],
      ))));
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_emptying, child: Scaffold(
    appBar: AppBar(title: const WorkspaceTitle('휴지통'), centerTitle: false, actions: [
      ListenableBuilder(listenable: elements, builder: (context, _) => TextButton.icon(
        onPressed: _emptying || elements.trash.isEmpty ? null : _emptyTrash,
        icon: const Icon(Icons.delete_sweep_outlined, size: 18), label: const Text('휴지통 비우기'))),
      const DesktopMenuAction()]),
    body: DesktopMenuBody(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(key: const ValueKey('trash-search'), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13), decoration: const InputDecoration(hintText: '생각·해시태그 찾기',
            prefixIcon: Icon(Icons.search, size: 18), prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 32),
            isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
        const SizedBox(height: 8),
        if (_emptying) const LinearProgressIndicator(),
        Expanded(child: ListenableBuilder(listenable: elements, builder: (context, _) {
          final records = elements.trash.values.where((r) => r.text.toLowerCase().contains(_query) ||
            r.tags.any((tag) => tag.toLowerCase().contains(_query.replaceFirst('#', '')))).toList()
            ..sort((a, b) => (b.deletedAt ?? b.createdAt).compareTo(a.deletedAt ?? a.createdAt));
          if (records.isEmpty) return Center(child: Text(_query.isEmpty ? '휴지통이 비어 있습니다.' : '검색 결과가 없습니다.'));
          return SingleChildScrollView(child: SizedBox(width: double.infinity, child: Wrap(spacing: 6, runSpacing: 6,
            children: [for (final record in records) WordBadge(word: record.text, query: _query, onTap: () => _open(record))])));
        })),
      ])),
    ))),
  ));
}

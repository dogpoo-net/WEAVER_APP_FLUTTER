import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'workspace_storage.dart';

/// Server implementations must reject an existing number unless overwrite is true.
abstract class NumberedBackupStore {
  Future<String?> read(String number);
  Future<void> write(String number, String data, {required bool overwrite});
}

Future<void> showNumberedBackup(BuildContext context, {
  required bool saving,
  required NumberedBackupStore? store,
  required String Function() export,
  required Future<void> Function(String, WorkspaceSnapshot) restore,
}) => showDialog<void>(context: context, builder: (_) => _BackupDialog(
  saving: saving, store: store, export: export, restore: restore));

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.saving, required this.store, required this.export, required this.restore});
  final bool saving;
  final NumberedBackupStore? store;
  final String Function() export;
  final Future<void> Function(String, WorkspaceSnapshot) restore;
  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}
class _BackupDialogState extends State<_BackupDialog> {
  final _number = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _number.dispose(); super.dispose(); }
  Future<bool> _confirm(String number) async => await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(widget.saving ? '$number번 백업을 덮어쓸까요?' : '현재 데이터를 모두 덮어쓸까요?'),
    content: Text(widget.saving ? '같은 번호에 저장된 파일을 지금 데이터로 교체합니다.' : '$number번 백업으로 원소·문단·프로젝트·상자·폴더·태그를 모두 교체합니다.'),
    actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('덮어쓰기'))],
  )) ?? false;
  Future<void> _run() async {
    if (_busy) return;
    final number = _number.text.trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(number)) {
      setState(() => _error = '1~12자리 숫자로 번호를 입력해주세요.'); return;
    }
    final store = widget.store;
    if (store == null) { setState(() => _error = '백업 저장 서버가 아직 연결되지 않았습니다.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final existing = await store.read(number);
      if (!mounted) return;
      if (widget.saving) {
        final overwrite = existing != null;
        if (overwrite && !await _confirm(number)) return;
        if (!mounted) return;
        await store.write(number, widget.export(), overwrite: overwrite);
      } else {
        if (existing == null) { setState(() => _error = '해당 번호의 백업이 없습니다.'); return; }
        // Validate the entire file before confirmation or any mutation.
        final snapshot = WorkspaceSnapshot.decode(existing);
        if (!await _confirm(number) || !mounted) return;
        await widget.restore(existing, snapshot);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.saving ? '$number번에 저장했습니다.' : '$number번 백업을 불러왔습니다.')));
      Navigator.pop(context);
    } on FormatException {
      if (mounted) setState(() => _error = '백업 파일이 올바르지 않습니다. 현재 데이터는 유지됩니다.');
    } catch (_) {
      if (mounted) setState(() => _error = '백업 서버 요청에 실패했습니다. 연결과 저장 권한을 확인해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(
    title: Text(widget.saving ? '번호로 저장하기' : '번호로 불러오기'),
    content: TextField(key: const ValueKey('backup-number'), controller: _number, autofocus: true,
      enabled: !_busy, keyboardType: TextInputType.number, maxLength: 12,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: '백업 번호', errorText: _error, errorMaxLines: 3),
      onSubmitted: (_) { if (!_busy) _run(); }),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('취소')),
      FilledButton(onPressed: _busy ? null : _run,
        child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.saving ? '저장하기' : '불러오기'))],
  ));
}

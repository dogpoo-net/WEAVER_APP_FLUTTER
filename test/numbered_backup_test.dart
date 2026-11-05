import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/numbered_backup.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

class MemoryBackups implements NumberedBackupStore {
  final files = <String, String>{};
  @override
  Future<String?> read(String number) async => files[number];
  @override
  Future<void> write(String number, String data, {required bool overwrite}) async {
    if (files.containsKey(number) && !overwrite) throw StateError('Conflict');
    files[number] = data;
  }
}
void main() {
  testWidgets('existing number only overwrites after confirmation', (tester) async {
    final store = MemoryBackups()..files['7'] = 'previous';
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showNumberedBackup(context, saving: true, store: store, export: () => 'new', restore: (_, _) async {}),
      child: const Text('open'))))));
    await tester.tap(find.text('open')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('backup-number')), '7');
    await tester.tap(find.text('저장하기')); await tester.pumpAndSettle();
    expect(find.text('7번 백업을 덮어쓸까요?'), findsOneWidget);
    await tester.tap(find.text('취소').last); await tester.pumpAndSettle();
    expect(store.files['7'], 'previous');
    await tester.tap(find.text('저장하기')); await tester.pumpAndSettle();
    await tester.tap(find.text('덮어쓰기')); await tester.pumpAndSettle();
    expect(store.files['7'], 'new');
  });
  testWidgets('restore validates the file and does not mutate data before confirmation', (tester) async {
    final store = MemoryBackups()..files['8'] = WorkspaceSnapshot.encode([])..files['9'] = 'invalid';
    var restores = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showNumberedBackup(context, saving: false, store: store, export: () => '', restore: (_, _) async { restores++; }),
      child: const Text('open'))))));
    await tester.tap(find.text('open')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('backup-number')), '9');
    await tester.tap(find.text('불러오기')); await tester.pumpAndSettle();
    expect(restores, 0);
    expect(find.text('현재 데이터를 모두 덮어쓸까요?'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('backup-number')), '8');
    await tester.tap(find.text('불러오기')); await tester.pumpAndSettle();
    expect(restores, 0);
    await tester.tap(find.text('취소').last); await tester.pumpAndSettle();
    expect(restores, 0);
    await tester.tap(find.text('불러오기')); await tester.pumpAndSettle();
    await tester.tap(find.text('덮어쓰기')); await tester.pumpAndSettle();
    expect(restores, 1);
  });
}

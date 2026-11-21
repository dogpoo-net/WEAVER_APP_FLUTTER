import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/storage/startup_preferences.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/features/sync/startup_recovery.dart';

import 'owned_workspace_test.dart' show DeltaApi, data;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recovery excludes duplicates and never deletes a server-only item', () {
    Map<String, dynamic> note(String id, String content) => {
      'kind': 'list:notes',
      'id': id,
      'value': {'content': content},
    };
    final common = note('same', 'same');
    final local = {'same': common, 'changed': note('changed', 'local')};
    final remote = {
      'same': common,
      'changed': note('changed', 'server'),
      'remote': note('remote', 'server only'),
    };
    expect(startupRecoveryDifferences(local, remote), {
      'changed': local['changed'],
    });
  });

  test('recovery preserves only confirmed local deletions and local edits', () {
    final local = <String, Map<String, dynamic>>{
      'unchanged': {'kind': 'map:colors', 'id': 'unchanged', 'value': 'old'},
    };
    final baseline = {
      ...local,
      'deleted': {'kind': 'map:colors', 'id': 'deleted', 'value': 'remove'},
    };
    final remote = <String, Map<String, dynamic>>{
      ...baseline,
      'unchanged': {'kind': 'map:colors', 'id': 'unchanged', 'value': 'new'},
    };
    final result = startupRecoveryDifferences(
      local,
      remote,
      baseline: baseline,
    );
    expect(result.keys, ['deleted']);
    expect(result['deleted']!['deleted'], true);
  });

  test(
    'a failed local migration loads the server into a separate cache',
    () async {
      final settings = await SharedPreferences.getInstance();
      final old = WorkspaceStorage(settings, owner: 'user');
      await old.write(data('device only'));
      await settings.setString(old.syncKey, 'broken checkpoint');

      final api = DeltaApi();
      addTearDown(api.dispose);
      final snapshot = splitWorkspace(data('server note'));
      await api.workspace('save', {'changes': snapshot.values.toList()});
      api.requests.clear();

      final recovered = await openStartupPreferences(
        openRecords: (_) async => throw const FormatException('invalid record'),
      );
      final root = WorkspaceStorage(recovered);
      await OwnedWorkspaces(root).initialize();
      final workspace = OwnedWorkspaces(root).scope('user');
      final sync = WorkspaceSync(workspace, api, isCurrent: () => true);
      addTearDown(sync.dispose);
      await sync.initialize();
      try {
        await discardStartupRecovery(sync);
      } on Exception {
        // The platform Hive directory is unavailable in this unit test.
      }
      expect(sync.ready, isTrue);
      expect(workspace.read(), contains('server note'));
      expect(old.read(), isNull);
      expect(settings.getString(old.syncKey), isNull);
      expect(api.requests, isEmpty);

      final restarted = await openStartupPreferences(
        openRecords: (_) async => throw StateError('should use recovery cache'),
      );
      expect(restarted.getString(workspace.workspaceKey), workspace.read());
    },
  );

  test('settings failure still provides a temporary workspace cache', () async {
    final restored = await openStartupPreferences(
      loadSettings: () async => throw StateError('settings unavailable'),
    );
    expect(restored, isA<RecoveryPreferences>());
    expect((restored as RecoveryPreferences).isTemporary, isTrue);
    final workspace = WorkspaceStorage(restored, owner: 'user');
    await workspace.write(data('server note'));
    expect(workspace.read(), contains('server note'));
  });
}

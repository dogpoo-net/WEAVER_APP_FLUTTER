import 'dart:convert';

import '../inbox/workspace_storage.dart';
import '../storage/startup_preferences.dart';
import 'owned_workspace.dart';

String startupRecoveryKey(WorkspaceStorage storage) =>
    storage.scoped('startup-recovery');

Map<String, Map<String, dynamic>> startupRecoveryItems(
  WorkspaceStorage storage,
) {
  final json = storage.preferences.getString(startupRecoveryKey(storage));
  return json == null ? {} : _items(jsonDecode(json));
}

Map<String, Map<String, dynamic>> _items(Object? value) => (value as Map).map(
  (key, row) => MapEntry(key as String, Map<String, dynamic>.from(row as Map)),
);

Map<String, Map<String, dynamic>> startupRecoveryDifferences(
  Map<String, Map<String, dynamic>> local,
  Map<String, Map<String, dynamic>> remote, {
  Map<String, Map<String, dynamic>>? baseline,
}) => {
  for (final key in {...local.keys, ...?baseline?.keys})
    if (!localCanvasView(local[key] ?? baseline?[key]) &&
        !sameItem(local[key], remote[key]) &&
        (baseline == null || !sameItem(local[key], baseline[key])))
      key: local[key] ?? {...baseline![key]!, 'deleted': true, 'value': null},
};

Future<void> discardStartupRecovery(WorkspaceSync engine) async {
  final storage = engine.storage;
  final prefs = storage.preferences;
  if (prefs is! RecoveryPreferences || !engine.ready || !engine.isCurrent()) return;
  final marker = storage.scoped('server-replacement-complete');
  if (prefs.getBool(marker) == true) return;
  await prefs.remove(startupRecoveryKey(storage));
  await prefs.discardOriginalWorkspace(storage.scoped(''));
  if (!await prefs.setBool(marker, true)) throw StateError('복구 완료 기록 실패');
}

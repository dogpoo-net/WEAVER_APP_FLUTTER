@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/storage/record_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main() {
  test(
    'IndexedDB and browser write lock preserve migrated workspace on reopen',
    () async {
      SharedPreferences.setMockInitialValues({
        WorkspaceStorage.key: '{"version":1,"elements":[],"notes":[]}',
      });
      final settings = await SharedPreferences.getInstance();
      var box = await Hive.openBox<String>('record-browser-test');
      await box.clear();
      var prefs = RecordPreferences(
        settings,
        box,
        reopen: () => Hive.openBox<String>('record-browser-test'),
      );
      await prefs.migrate();
      expect(settings.containsKey(WorkspaceStorage.key), isFalse);
      await prefs.setString(
        WorkspaceStorage.key,
        '{"version":1,"elements":[{"id":"a","text":"test"}],"notes":[]}',
      );
      await box.close();
      box = await Hive.openBox<String>('record-browser-test');
      prefs = RecordPreferences(settings, box);
      expect(prefs.getString(WorkspaceStorage.key), contains('test'));
      await prefs.remove(WorkspaceStorage.key);
      expect(prefs.getString(WorkspaceStorage.key), isNull);
      await box.deleteFromDisk();
    },
  );
}

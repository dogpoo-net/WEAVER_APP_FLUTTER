import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/storage/record_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/graph_layout.dart';
import 'package:weaver/features/sync/owned_workspace.dart';

import 'owned_workspace_test.dart' show DeltaApi, data;

class FailingManifestBox implements Box<String> {
  FailingManifestBox(this.delegate);
  final Box<String> delegate;
  @override
  String? get(dynamic key, {String? defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  Future<void> putAll(Map<dynamic, String> entries) => delegate.putAll(entries);
  @override
  Future<void> flush() => delegate.flush();
  @override
  Future<void> put(dynamic key, String value) async {
    if (key is String && key.startsWith('manifest:')) {
      throw StateError('injected manifest write failure');
    }
    await delegate.put(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Box<String> box;
  late SharedPreferences settings;
  late RecordPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('weaver-record-test');
    box = await Hive.openBox<String>('records', path: dir.path);
    prefs = RecordPreferences(settings, box);
  });
  tearDown(() async {
    await box.close();
    await dir.delete(recursive: true);
  });
  test(
    'migrates each scope and checkpoint without touching settings',
    () async {
      final key = WorkspaceStorage(
        settings,
        owner: 'account/space',
      ).workspaceKey;
      final raw = jsonEncode({
        'version': 1,
        'elements': [
          {'id': 'a', 'text': 'hello'},
        ],
      });
      await settings.setString(key, raw);
      await settings.setString('weaver.theme.v1', 'dark');
      await prefs.migrate();
      expect(settings.containsKey(key), isFalse);
      expect(prefs.getString(key), raw);
      expect(settings.getString('weaver.theme.v1'), 'dark');
      expect(prefs.getKeys(), contains(key));
      await box.close();
      box = await Hive.openBox<String>('records', path: dir.path);
      prefs = RecordPreferences(settings, box);
      expect(prefs.getString(key), raw);
      await prefs.migrate();
      expect(prefs.getString(key), raw);
    },
  );
  test('bad legacy JSON is retained and stops migration', () async {
    await settings.setString(WorkspaceStorage.key, '{broken');
    await expectLater(prefs.migrate(), throwsFormatException);
    expect(settings.getString(WorkspaceStorage.key), '{broken');
  });
  test('workspace writes, deletion and isolation use records', () async {
    final a = WorkspaceStorage(prefs, owner: 'a'),
        b = WorkspaceStorage(prefs, owner: 'b');
    String raw(String text) => jsonEncode({
      'version': 1,
      'elements': [
        {'id': 'memo', 'text': text},
      ],
      'notes': [],
    });
    await a.write(raw('one'));
    await b.write(raw('other'));
    await a.write(raw('two'));
    expect(a.read(), raw('two'));
    expect(prefs.getString('${a.workspaceKey}.previous'), raw('one'));
    expect(settings.containsKey(a.workspaceKey), isFalse);
    await a.clear();
    expect(a.read(), isNull);
    expect(b.read(), raw('other'));
  });
  test(
    'same snapshot writes nothing and updates remove obsolete chunks',
    () async {
      const key = WorkspaceStorage.key;
      String data(String text) => jsonEncode({
        'elements': [
          {'id': 'a', 'text': text},
          {'id': 'b', 'text': 'fixed'},
        ],
      });
      await prefs.setString(key, data('one'));
      final first = box.keys.toSet();
      await prefs.setString(key, data('one'));
      expect(box.keys.toSet(), first);
      await prefs.setString(key, data('two'));
      final next = box.keys.toSet();
      expect(next.difference(first).length, 1);
      expect(first.difference(next).length, 1);
      expect(prefs.getString(key), data('two'));
    },
  );
  test('direct model saves capture state before awaits and retain previous version on no-op', () async {
    final storage = WorkspaceStorage(prefs, owner: 'direct');
    var changes = 0;
    storage.onChanged = () => changes++;
    pageGraphLayout = GraphLayout();
    pageGraphLayout.layers.add('original');
    final note = Note('first', id: 'note-a');
    final pending = storage.writeSnapshot([note]);
    note.content = 'second';
    pageGraphLayout.layers.add('later');
    await pending;
    final first = storage.read();
    expect((jsonDecode(first!)['notes'] as List).single['content'], 'first');
    expect(jsonDecode(first)['graphLayout']['layers'], ['original']);
    await storage.writeSnapshot([note]);
    final previous = prefs.getString('${storage.workspaceKey}.previous');
    expect(previous, first);
    expect(changes, 2);
    await storage.writeSnapshot([note]);
    expect(changes, 2);
    expect(prefs.getString('${storage.workspaceKey}.previous'), previous);
    pageGraphLayout = GraphLayout();
  });
  test('failed manifest commit preserves old snapshot and orphan records are collected', () async {
    const key = WorkspaceStorage.key;
    await prefs.setString(key, '{"elements":[{"id":"a","text":"old"}]}');
    final count = box.length;
    final broken = RecordPreferences(settings, FailingManifestBox(box));
    await expectLater(
      broken.setString(key, '{"elements":[{"id":"a","text":"new"}]}'),
      throwsStateError,
    );
    expect(box.length, greaterThan(count));
    expect(prefs.getString(key), contains('old'));
    await prefs.migrate();
    expect(box.length, count);
  });
  test(
    'sync checkpoints restart and guest isolation work through record storage',
    () async {
      final owned = OwnedWorkspaces(WorkspaceStorage(prefs));
      await owned.initialize();
      final storage = owned.scope('account-a');
      final api = DeltaApi();
      final sync = WorkspaceSync(storage, api, isCurrent: () => true);
      await sync.initialize();
      await storage.write(data('first'));
      await sync.flush();
      expect(settings.containsKey(storage.syncKey), isFalse);
      expect(prefs.containsKey(storage.syncKey), isTrue);
      expect((await owned.guest()).read(), isNull);
      sync.dispose();
      final next = WorkspaceSync(storage, api, isCurrent: () => true);
      await next.initialize();
      expect(storage.read(), contains('first'));
      await storage.write(data('second'));
      await next.flush();
      expect(api.requests, isNotEmpty);
      next.dispose();
      api.dispose();
    },
  );
  test('all content namespaces are routed and UI settings remain settings', () {
    final s = WorkspaceStorage(settings, owner: 'account/workspace');
    for (final name in [
      'weaver.workspace.v1',
      'weaver.workspace.v1.previous',
      'weaver.graph-layouts.v1',
      'sync.v1',
      'document.draft.a',
      'offline-baseline',
      'offline-recovery',
      'network-recovery-base',
      'canvas.outbox.v1',
    ]) {
      expect(RecordPreferences.stores(s.scoped(name)), isTrue, reason: name);
    }
    expect(RecordPreferences.stores(s.scoped('offline-active')), isFalse);
    expect(RecordPreferences.stores('weaver.overviewLastTab.v1'), isFalse);
  });
}

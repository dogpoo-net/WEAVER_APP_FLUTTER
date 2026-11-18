import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'json_records.dart';
import 'record_lock.dart';

/// Compatibility boundary: settings remain preferences; workspace JSON is
/// persisted as individual versioned records with one commit manifest.
class RecordPreferences implements SharedPreferences {
  RecordPreferences(this.settings, this.box, {this.reopen})
    : _observedRevision = RecordLock().revision;
  final SharedPreferences settings;
  Box<String> box;
  final Future<Box<String>> Function()? reopen;
  final _lock = RecordLock();
  String? _observedRevision;
  bool _changed = false;
  Map<String, String>? _refreshing;
  String? _get(String key) =>
      _refreshing != null ? _refreshing![key] : box.get(key);
  bool _contains(String key) => _refreshing != null
      ? _refreshing!.containsKey(key)
      : box.containsKey(key);
  Iterable<dynamic> get _keys => _refreshing?.keys ?? box.keys;
  Future<void> _queue = Future.value();
  final _cache = <String, ({String manifest, String raw})>{};
  void _remember(String key, String manifest, String raw) {
    _cache.remove(key);
    _cache[key] = (manifest: manifest, raw: raw);
    while (_cache.length > 4) {
      _cache.remove(_cache.keys.first);
    }
  }

  static Future<RecordPreferences> open(SharedPreferences settings) async {
    // Same Hive directory as MediaStorage, a separate database file/IDB box.
    await Hive.initFlutter('weaver-media');
    final result = RecordPreferences(
      settings,
      await Hive.openBox<String>('workspace-records-v1'),
      reopen: () => Hive.openBox<String>('workspace-records-v1'),
    );
    result._observedRevision = null;
    await result.migrate();
    return result;
  }

  static bool stores(String key) {
    final name = key.startsWith('weaver.owned.')
        ? key.substring(key.indexOf('.', 13) + 1)
        : key;
    return name == 'weaver.workspace.v1' ||
        name.startsWith('weaver.workspace.v1.') ||
        name == 'weaver.graph-layouts.v1' ||
        name == 'sync.v1' ||
        name.startsWith('document.draft.') ||
        name == 'network-recovery-base' ||
        name == 'canvas.outbox.v1' ||
        name == 'offline-baseline' ||
        name == 'offline-recovery';
  }

  String _scope(String key) => base64Url.encode(utf8.encode(key));
  String _manifest(String key) => 'manifest:${_scope(key)}';
  String _record(String key, String ref) => 'record:${_scope(key)}:$ref';
  Future<T> _serial<T>(Future<T> Function() action) {
    final task = _queue
        .catchError((Object _) {})
        .then(
          (_) => _lock.exclusive(() async {
            final revision = _lock.revision;
            if (reopen != null && revision != _observedRevision) {
              _refreshing = Map<String, String>.from(box.toMap());
              try {
                await box.close();
                box = await reopen!();
                _cache.clear();
              } finally {
                if (box.isOpen) _refreshing = null;
              }
            }
            _observedRevision = revision;
            _changed = false;
            try {
              return await action();
            } finally {
              if (_changed) {
                _lock.changed();
                _observedRevision = _lock.revision;
              }
            }
          }),
        );
    _queue = task.then<void>((_) {}).catchError((Object _) {});
    return task;
  }

  Future<void> migrate() => _serial(() async {
    for (final key in settings.getKeys().where(stores).toList()) {
      final raw = settings.getString(key);
      if (raw == null) continue;
      if (!box.containsKey(_manifest(key))) await _put(key, raw);
      // Read every referenced record before removing the source. Any failure
      // leaves legacy data intact and aborts initialization.
      JsonRecords.join(
        jsonDecode(box.get(_manifest(key))!),
        (ref) => box.get(_record(key, ref)),
      );
      if (!await settings.remove(key))
        throw StateError('Local migration cleanup failed');
    }
    // Interrupted writes can leave unreachable records; remove only after every
    // committed manifest is readable. Never touch other Hive boxes (media).
    final reachable = <String>{};
    for (final manifest in box.keys.whereType<String>().where(
      (key) => key.startsWith('manifest:'),
    )) {
      final scope = manifest.substring(9);
      final tree = jsonDecode(box.get(manifest)!);
      for (final ref in JsonRecords.refs(
        tree,
        read: (ref) => box.get('record:$scope:$ref'),
      )) {
        if (!box.containsKey('record:$scope:$ref'))
          throw const FormatException('Incomplete local database');
      }
      reachable.addAll(
        JsonRecords.refs(
          tree,
          read: (ref) => box.get('record:$scope:$ref'),
        ).map((ref) => 'record:$scope:$ref'),
      );
    }
    final garbage = box.keys
        .whereType<String>()
        .where((key) => key.startsWith('record:') && !reachable.contains(key))
        .toList();
    if (garbage.isNotEmpty) {
      await box.deleteAll(garbage);
      _changed = true;
    }
  });
  Future<bool> _put(String key, String raw) =>
      _putValue(key, jsonDecode(raw), raw: raw);
  Future<bool> _putValue(String key, Object? value, {String? raw}) async {
    final old = box.get(_manifest(key));
    if (raw != null &&
        old != null &&
        _cache[key]?.manifest == old &&
        _cache[key]?.raw == raw)
      return true;
    final split = _split(key, value);
    return _commit(key, split, raw: raw);
  }

  JsonRecords _split(String key, Object? value) {
    final old = box.get(_manifest(key));
    final previous = <String, String>{
      if (old != null)
        for (final ref in JsonRecords.refs(
          jsonDecode(old),
          read: (ref) => box.get(_record(key, ref)),
        ))
          ref.substring(0, ref.lastIndexOf('.')): ref,
    };
    return JsonRecords.splitValue(
      value,
      reuse: (identity, encoded) {
        final ref = previous[identity];
        return ref != null && box.get(_record(key, ref)) == encoded
            ? ref
            : null;
      },
    );
  }

  Future<bool> _commit(String key, JsonRecords split, {String? raw}) async {
    final old = box.get(_manifest(key));
    final manifest = jsonEncode(split.tree);
    if (old != manifest) {
      final added = <String, String>{
        for (final e in split.records.entries)
          if (!box.containsKey(_record(key, e.key)))
            _record(key, e.key): e.value,
      };
      _changed = true;
      await box.putAll(added);
      await box.flush();
      // Commit point. Old records remain reachable until this single write.
      await box.put(_manifest(key), manifest);
      await box.flush();
      if (old != null) {
        final removed = JsonRecords.refs(
          jsonDecode(old),
          read: (ref) => box.get(_record(key, ref)),
        ).difference(split.records.keys.toSet());
        // Garbage collection is not part of commit success; never ask a caller
        // to roll back an already committed workspace for cleanup failure.
        try {
          await box.deleteAll(removed.map((ref) => _record(key, ref)));
        } catch (_) {}
      }
    }
    if (raw != null) {
      _remember(key, manifest, raw);
    } else if (old != manifest) {
      _cache.remove(key);
    }
    return true;
  }

  /// The caller supplies an immutable captured model, avoiding whole JSON
  /// encode/decode on the ordinary memo-save path.
  Future<bool> setJson(String key, Object? value, {String? previousKey}) =>
      _serial(() async {
        if (!stores(key)) throw ArgumentError('Not a content key');
        final split = _split(key, value);
        if (box.get(_manifest(key)) == jsonEncode(split.tree)) return false;
        if (previousKey != null) await _copy(key, previousKey);
        await _commit(key, split);
        return true;
      });
  Future<void> _copy(String source, String target) async {
    final manifest = box.get(_manifest(source));
    if (manifest == null) return;
    final tree = jsonDecode(manifest);
    final parts = JsonRecords(tree, {
      for (final ref in JsonRecords.refs(
        tree,
        read: (ref) => box.get(_record(source, ref)),
      ))
        ref:
            box.get(_record(source, ref)) ??
            (throw const FormatException('Missing backup source')),
    });
    await _commit(target, parts, raw: _cache[source]?.raw);
  }

  @override
  String? getString(String key) {
    if (!stores(key)) return settings.getString(key);
    final raw = _get(_manifest(key));
    if (raw == null) return settings.getString(key);
    final cached = _cache[key];
    if (cached?.manifest == raw) return cached!.raw;
    final value = JsonRecords.join(
      jsonDecode(raw),
      (ref) => _get(_record(key, ref)),
    );
    _remember(key, raw, value);
    return value;
  }

  @override
  Future<bool> setString(String key, String value) => !stores(key)
      ? settings.setString(key, value)
      : _serial(() async {
          await _put(key, value);
          if (settings.containsKey(key) && !await settings.remove(key))
            throw StateError('Legacy cleanup failed');
          return true;
        });
  @override
  Future<bool> remove(String key) => !stores(key)
      ? settings.remove(key)
      : _serial(() async {
          if (settings.containsKey(key) && !await settings.remove(key))
            return false;
          _cache.remove(key);
          _changed = true;
          await box.delete(_manifest(key));
          await box.flush();
          try {
            await box.deleteAll(
              box.keys
                  .whereType<String>()
                  .where((k) => k.startsWith('record:${_scope(key)}:'))
                  .toList(),
            );
          } catch (_) {}
          return true;
        });
  @override
  Set<String> getKeys() => {
    ...settings.getKeys(),
    for (final key in _keys.whereType<String>())
      if (key.startsWith('manifest:'))
        utf8.decode(base64Url.decode(key.substring(9))),
  };
  @override
  bool containsKey(String key) => stores(key)
      ? _contains(_manifest(key)) || settings.containsKey(key)
      : settings.containsKey(key);
  @override
  Object? get(String key) => stores(key) ? getString(key) : settings.get(key);
  @override
  Future<void> reload() => _serial(() => settings.reload());
  @override
  bool? getBool(String key) => settings.getBool(key);
  @override
  int? getInt(String key) => settings.getInt(key);
  @override
  double? getDouble(String key) => settings.getDouble(key);
  @override
  List<String>? getStringList(String key) => settings.getStringList(key);
  @override
  Future<bool> setBool(String key, bool value) => settings.setBool(key, value);
  @override
  Future<bool> setInt(String key, int value) => settings.setInt(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      settings.setDouble(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      settings.setStringList(key, value);
  @override
  Future<bool> commit() async => true;
  @override
  Future<bool> clear() => _serial(() async {
    _changed = true;
    await box.clear();
    await box.flush();
    _cache.clear();
    return settings.clear();
  });
}

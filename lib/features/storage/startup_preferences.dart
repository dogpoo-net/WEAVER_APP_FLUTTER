import 'package:shared_preferences/shared_preferences.dart';

import 'record_preferences.dart';

/// Opens the regular store, or starts with a separate cache when it is unusable.
Future<SharedPreferences> openStartupPreferences({
  Future<SharedPreferences> Function() loadSettings =
      SharedPreferences.getInstance,
  Future<SharedPreferences> Function(SharedPreferences) openRecords =
      RecordPreferences.open,
}) async {
  SharedPreferences? settings;
  try {
    settings = await loadSettings();
    if (settings.getBool(RecoveryPreferences.marker) != true) {
      return await openRecords(settings);
    }
  } catch (_) {
    // Leave the original record box and legacy preference keys intact.
  }
  if (settings != null) {
    try {
      if (await settings.setBool(RecoveryPreferences.marker, true)) {
        return RecoveryPreferences(settings);
      }
    } catch (_) {
      // A temporary cache still lets the account load from the server.
    }
  }
  return RecoveryPreferences(null);
}

class RecoveryPreferences implements SharedPreferences {
  RecoveryPreferences(this._settings);

  static const _prefix = 'weaver.startup-recovery.v1:';
  static const marker = '${_prefix}active';
  static const _data = '${_prefix}data:';
  final SharedPreferences? _settings;
  final Map<String, Object> _temporary = {};

  bool get isTemporary => _settings == null;

  Future<void> discardOriginalWorkspace(String prefix) async {
    final settings = _settings;
    if (settings == null) return;
    Future<void> clearScope(SharedPreferences source) async {
      for (final key in source.getKeys().where((key) => key.startsWith(prefix)).toList()) {
        if (!await source.remove(key)) throw StateError('기기 캐시 삭제 실패');
      }
    }
    await clearScope(settings);
    final records = await RecordPreferences.open(settings, migrateLegacy: false);
    try {
      await clearScope(records);
    } finally {
      await records.box.close();
    }
  }

  @override
  Object? get(String key) => _settings?.get('$_data$key') ?? _temporary[key];

  @override
  Set<String> getKeys() =>
      _settings
          ?.getKeys()
          .where((key) => key.startsWith(_data))
          .map((key) => key.substring(_data.length))
          .toSet() ??
      _temporary.keys.toSet();

  @override
  bool containsKey(String key) => getKeys().contains(key);
  @override
  bool? getBool(String key) => get(key) as bool?;
  @override
  double? getDouble(String key) => get(key) as double?;
  @override
  int? getInt(String key) => get(key) as int?;
  @override
  String? getString(String key) => get(key) as String?;
  @override
  List<String>? getStringList(String key) =>
      (get(key) as List?)?.cast<String>().toList();

  Future<bool> _set<T extends Object>(
    String key,
    T value,
    Future<bool> Function(String, T)? persist,
  ) async {
    if (persist != null) return persist('$_data$key', value);
    _temporary[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) =>
      _set(key, value, _settings?.setBool);
  @override
  Future<bool> setDouble(String key, double value) =>
      _set(key, value, _settings?.setDouble);
  @override
  Future<bool> setInt(String key, int value) =>
      _set(key, value, _settings?.setInt);
  @override
  Future<bool> setString(String key, String value) =>
      _set(key, value, _settings?.setString);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, value.toList(), _settings?.setStringList);

  @override
  Future<bool> remove(String key) async {
    if (_settings case final settings?) return settings.remove('$_data$key');
    _temporary.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    for (final key in getKeys()) {
      if (!await remove(key)) return false;
    }
    return true;
  }

  @override
  Future<void> reload() async => _settings?.reload();
  @override
  Future<bool> commit() async => true;
}

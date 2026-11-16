import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences, separate for each collection. Keep the selected
/// count synchronously available when a tab is recreated; clamp only for display.
class GridColumnsPreference {
  GridColumnsPreference(this.key);
  final String key;
  int? value;
  bool loaded = false;
  Future<void>? _loading;
  Future<void>? _writing;
  Future<void> load() {
    if (loaded) return Future.value();
    return _loading ??= (() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getInt(key);
        if (!loaded && saved != null && saved >= 1 && saved <= 64)
          value = saved;
      } finally {
        loaded = true;
      }
    })();
  }

  Future<void> save(int columns) {
    value = columns;
    loaded = true;
    final previous = _writing;
    final task = (() async {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt(key, columns))
        throw StateError('Column preference save failed');
    })();
    _writing = task.catchError((Object _) {});
    return task;
  }
}

GridColumnsPreference thoughtGridColumns = GridColumnsPreference(
  'weaver.thoughtGridColumns.v1',
);
GridColumnsPreference photoGridColumns = GridColumnsPreference(
  'weaver.photoGridColumns.v1',
);

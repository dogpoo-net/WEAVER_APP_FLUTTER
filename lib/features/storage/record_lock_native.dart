// Hive holds the native database file lock; the adapter serializes its writes.
class RecordLock {
  String get revision => '';
  Future<T> exclusive<T>(Future<T> Function() action) => action();
  void changed() {}
}

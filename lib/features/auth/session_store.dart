abstract class SessionStore {
  bool get isWeb;
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

import 'package:weaver/features/auth/session_store.dart';
class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.isWeb = false});
  @override final bool isWeb;
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async { this.value = value; }
  @override Future<void> clear() async { value = null; }
}

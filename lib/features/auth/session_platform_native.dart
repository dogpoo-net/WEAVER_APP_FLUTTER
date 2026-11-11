import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'session_store.dart';
http.Client sessionHttpClient() => http.Client();
SessionStore sessionStore() => NativeSessionStore();
class NativeSessionStore implements SessionStore {
  static const _key = 'weaver.email.refresh.v2';
  final FlutterSecureStorage storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false),
  );
  @override bool get isWeb => false;
  @override Future<String?> read() => storage.read(key: _key);
  @override Future<void> write(String value) => storage.write(key: _key, value: value);
  @override Future<void> clear() => storage.delete(key: _key);
}

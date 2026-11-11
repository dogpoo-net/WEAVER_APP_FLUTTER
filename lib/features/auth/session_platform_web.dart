import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:web/web.dart' as web;
import 'session_store.dart';
http.Client sessionHttpClient() => BrowserClient()..withCredentials = true;
SessionStore sessionStore() => WebSessionStore();
class WebSessionStore implements SessionStore {
  static const _key = 'weaver.email.tab.v2';
  @override bool get isWeb => true;
  // Only tab ID/proof are stored here. Authentication cookie is HttpOnly.
  @override Future<String?> read() async => web.window.sessionStorage.getItem(_key);
  @override Future<void> write(String value) async => web.window.sessionStorage.setItem(_key, value);
  @override Future<void> clear() async => web.window.sessionStorage.removeItem(_key);
}

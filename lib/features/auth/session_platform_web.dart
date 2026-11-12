import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:web/web.dart' as web;
import 'session_store.dart';
http.Client sessionHttpClient() => BrowserClient()..withCredentials = true;
SessionStore sessionStore() => WebSessionStore();
class WebSessionStore implements SessionStore {
  static const _key = 'weaver.email.tab.v2';
  @override bool get isWeb => true;
  // Browser-restorable ID/proof only; authentication remains in an HttpOnly cookie.
  @override Future<String?> read() async => web.window.localStorage.getItem(_key) ?? web.window.sessionStorage.getItem(_key);
  @override Future<void> write(String value) async { web.window.localStorage.setItem(_key, value); web.window.sessionStorage.removeItem(_key); }
  @override Future<void> clear() async { web.window.localStorage.removeItem(_key); web.window.sessionStorage.removeItem(_key); }
}

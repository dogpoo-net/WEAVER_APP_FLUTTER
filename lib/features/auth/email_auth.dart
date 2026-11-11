import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'session_platform.dart';
import 'session_store.dart';
import 'oauth_window.dart';

class EmailAuthFailure implements Exception {
  const EmailAuthFailure(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401;
  @override String toString() => message;
}

class EmailAuthApi {
  EmailAuthApi({http.Client? client, Uri? base, SessionStore? store})
      : _client = client ?? sessionHttpClient(),
        store = store ?? sessionStore(),
        _base = base ?? Uri.parse(const String.fromEnvironment('WEAVER_AUTH_URL',
            defaultValue: 'https://api.dogpoo.net/dogpoo/weaver/api/auth/'));
  final http.Client _client;
  final Uri _base;
  final SessionStore store;
  Map<String, String>? _tab;
  String? _refreshToken;
  String? _refreshId;
  String? accessToken;
  Future<Map<String, dynamic>?>? _refreshing;
  bool _disposed = false;
  int _oauthAttempt = 0;
  void cancelOAuth() { _oauthAttempt++; }
  String get _platform => store.isWeb ? 'web' : 'native';
  String _random(int count) => base64UrlEncode(List<int>.generate(count, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  Future<Map<String, dynamic>> post(String action, Map<String, Object?> body,
      {String? sessionToken}) async {
    try {
      final response = await _client.post(_base.resolve(action), headers: {
        'Content-Type': 'application/json',
        if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
        if (store.isWeb && _tab != null) 'X-Weaver-Tab': _tab!['id']!,
        if (store.isWeb && _tab != null) 'X-Weaver-Proof': _tab!['proof']!,
      }, body: jsonEncode(body)).timeout(const Duration(seconds: 35));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw EmailAuthFailure(data is Map && data['message'] is String
            ? data['message'] as String : '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.', status: response.statusCode);
      }
      return Map<String, dynamic>.from(data as Map);
    } on EmailAuthFailure { rethrow; }
    catch (_) { throw const EmailAuthFailure('서버에 연결하지 못했습니다. 연결을 확인하고 다시 시도해주세요.'); }
  }
  Future<void> _load() async {
    final raw = await store.read();
    if (store.isWeb) {
      try {
        _tab = raw == null ? null : Map<String, String>.from(jsonDecode(raw) as Map);
        if (_tab != null && (!RegExp(r'^[a-f0-9]{32}$').hasMatch(_tab!['id'] ?? '') ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(_tab!['proof'] ?? ''))) {
          throw const FormatException('Invalid tab state');
        }
      } catch (_) { _tab = null; await store.clear(); }
    } else {
      if (raw == null) { _refreshToken = null; _refreshId = null; return; }
      final data = jsonDecode(raw) as Map;
      _refreshToken = data['refreshToken'] as String;
      _refreshId = data['requestId'] as String?;
    }
  }
  Future<Map<String, dynamic>?> restore() async {
    await _load();
    if (store.isWeb ? _tab == null : _refreshToken == null) return null;
    return refresh();
  }
  Future<Map<String, dynamic>> login(String email, String password) => _login('login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> loginKakao(String token) => _login('kakao', {'kakaoToken': token});
  Future<void> linkKakao(String token) async {
    final renewed = await refresh();
    if (renewed == null) throw const EmailAuthFailure('다시 로그인해주세요.', status: 401);
    await post('session/$_platform/kakao/link', {'kakaoToken': token}, sessionToken: accessToken);
  }
  Future<void> _prepareTab() async {
    if (store.isWeb) {
      await _load();
      _tab ??= {'id': List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join(), 'proof': _random(32)};
      // Persist tab proof before issuing a cookie. Storage failure must not create an inaccessible session.
      await store.write(jsonEncode(_tab));
    }
  }
  Future<Map<String, dynamic>?> loginBrowser(String provider, {bool link = false}) async {
    final window = OAuthWindow(); // Open synchronously within the browser's user gesture.
    final attempt = ++_oauthAttempt;
    try {
      await _prepareTab();
      if (link && await refresh() == null) throw const EmailAuthFailure('다시 로그인해주세요.', status: 401);
      final proof = _random(32);
      final flow = await post('session/$_platform/$provider/start', {'proof': proof, 'link': link}, sessionToken: accessToken);
      final url = flow['authorizeUrl'] as String;
      final target = Uri.parse(url);
      if (target.scheme != 'https' || !{'nid.naver.com', 'github.com', 'gitlab.com'}.contains(target.host)) throw const EmailAuthFailure('로그인 주소를 확인하지 못했습니다.');
      await window.navigate(url);
      for (var i = 0; i < 300; i++) {
        if (_disposed || attempt != _oauthAttempt || window.closed) return null;
        final result = await post('session/$_platform/$provider/finish', {'flow': flow['flow'] as String, 'proof': proof}, sessionToken: accessToken);
        if (result['pending'] != true) {
          if (!link) await _accept(result);
          return result;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      throw const EmailAuthFailure('로그인 시간이 만료되었습니다. 다시 시도해주세요.');
    } on EmailAuthFailure { rethrow; }
    catch (_) { throw const EmailAuthFailure('로그인 창을 열지 못했습니다. 브라우저의 팝업 설정을 확인해주세요.'); }
    finally { window.close(); }
  }
  Future<Map<String, dynamic>> _login(String action, Map<String,String> credentials) async {
    await _prepareTab();
    final result = await post('session/$_platform/$action', credentials);
    await _accept(result);
    return result;
  }
  Future<void> _accept(Map<String, dynamic> result) async {
    if (_disposed) return;
    if (!store.isWeb) {
      final token = result['refreshToken'] as String;
      try { await store.write(jsonEncode({'refreshToken': token})); }
      catch (_) {
        try { await post('session/native/logout', {'refreshToken': token}); } catch (_) {}
        rethrow;
      }
      _refreshToken = token;
      _refreshId = null;
      accessToken = result['accessToken'] as String;
    }
  }
  Future<Map<String, dynamic>?> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<Map<String, dynamic>?> _refresh() async {
    try {
      if (!store.isWeb) {
        _refreshId ??= _random(32);
        await store.write(jsonEncode({'refreshToken': _refreshToken, 'requestId': _refreshId}));
      }
      final result = await post('session/$_platform/refresh', {
        if (!store.isWeb) 'refreshToken': _refreshToken!,
        if (!store.isWeb) 'refreshId': _refreshId!,
      });
      await _accept(result);return result;
    } on EmailAuthFailure catch (e) {
      if (e.unauthorized) { await clear();return null; }
      rethrow; // Network failure does not erase a long-lived device credential.
    }
  }
  Future<void> logout({bool all = false}) async {
    if (_refreshing != null) { try { await _refreshing; } catch (_) {} }
    await _load();
    if (!store.isWeb && _refreshId != null) await refresh();
    if (store.isWeb ? _tab == null : _refreshToken == null) {
      if (all) throw const EmailAuthFailure('전체 로그아웃하려면 다시 로그인해주세요.', status: 401);
      await clear();return;
    }
    try {
      await post('session/$_platform/${all ? 'logout-all' : 'logout'}', {if (!store.isWeb) 'refreshToken': _refreshToken!});
    } on EmailAuthFailure catch (e) { if (!e.unauthorized || all) rethrow; }
    await clear();
  }
  Future<void> clear() async { await store.clear();_tab = null;_refreshToken = null;_refreshId = null;accessToken = null; }
  void dispose() { _disposed = true;cancelOAuth();_client.close(); }
}

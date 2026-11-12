import 'dart:async';
import 'oauth_window_handle.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'session_platform.dart';
import 'session_store.dart';
import 'session_peer.dart';
import 'oauth_window.dart';

class EmailAuthFailure implements Exception {
  const EmailAuthFailure(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401;
  @override String toString() => message;
}

class EmailAuthApi {
  EmailAuthApi({http.Client? client, Uri? base, SessionStore? store, OAuthWindowHandle Function()? oauthWindowFactory})
      : _windowFactory = oauthWindowFactory ?? OAuthWindow.new,
        _client = client ?? sessionHttpClient(),
        store = store ?? sessionStore(),
        _base = base ?? Uri.parse(const String.fromEnvironment('WEAVER_AUTH_URL',
            defaultValue: 'https://api.dogpoo.net/dogpoo/weaver/api/auth/')) {
    _peer = SessionPeer(available: () => !_disposed && _authenticated && _tab != null, attach: (tab, proof) async {
      await post('session/web/attach', {'tabId': tab, 'proof': proof});
    });
  }
  final OAuthWindowHandle Function() _windowFactory;
  Completer<void>? _oauthCancelled;
  final http.Client _client;
  final Uri _base;
  final SessionStore store;
  late final SessionPeer _peer;
  bool _authenticated = false;
  Map<String, String>? _tab;
  String? _refreshToken;
  String? _refreshId;
  String? accessToken;
  Future<Map<String, dynamic>?>? _refreshing;
  bool _disposed = false;
  int _oauthAttempt = 0;
  void cancelOAuth() { _oauthAttempt++; final cancel = _oauthCancelled; if (cancel != null && !cancel.isCompleted) cancel.complete(); }
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
      dynamic data;
      try { data = jsonDecode(utf8.decode(response.bodyBytes)); } on FormatException { /* Proxies and server errors can return HTML instead of JSON. */ }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw EmailAuthFailure(data is Map && data['message'] is String
            ? data['message'] as String : response.statusCode >= 500 ? '서버에서 요청을 처리하지 못했습니다. (${response.statusCode}) 저장한 로컬 자료는 유지됩니다. 잠시 후 다시 시도해주세요.' : '요청을 처리하지 못했습니다. (${response.statusCode})', status: response.statusCode);
      }
      if(data is! Map)throw const EmailAuthFailure('서버 응답 형식이 올바르지 않습니다. 저장한 로컬 자료는 유지됩니다.');
      return Map<String, dynamic>.from(data);
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
    if (store.isWeb ? _tab != null : _refreshToken != null) {
      final restored = await refresh();
      if (restored != null) return restored;
    }
    if (store.isWeb && Uri.base.fragment.startsWith('invite=')) {
      await _prepareTab();
      if (await _peer.request(_tab!['id']!, _tab!['proof']!)) return refresh();
      await clear();
    }
    return null;
  }
  Future<Map<String, dynamic>> login(String email, String password) => _login('login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> loginGoogle(String? token, {String? accessToken}) => _login('google', {'idToken': ?token, 'googleAccessToken': ?accessToken});
  Future<Map<String, dynamic>> _authenticatedPost(String action, Map<String, Object?> body) async {
    if (!store.isWeb && accessToken == null && await refresh() == null) {
      throw const EmailAuthFailure('다시 로그인해주세요.', status: 401);
    }
    try {
      return await post(action, body, sessionToken: accessToken);
    } on EmailAuthFailure catch (error) {
      if (!error.unauthorized) rethrow;
      if (await refresh() == null) throw const EmailAuthFailure('세션이 만료되었습니다. 다시 로그인해주세요.', status: 401);
      return post(action, body, sessionToken: accessToken);
    }
  }
  Future<Map<String, dynamic>> workspace(String action, Map<String, Object?> body) =>
      _authenticatedPost('session/$_platform/workspace/$action', body);
  Future<Map<String, dynamic>> profile(String action, [Map<String, Object?> body = const {}]) =>
      _authenticatedPost('session/$_platform/profile/$action', body);
  Future<void> linkGoogle(String? token, {String? accessToken, bool Function()? isCurrent}) async {
    if (await refresh() == null) throw const EmailAuthFailure('다시 로그인해주세요.', status: 401);
    if (isCurrent != null && !isCurrent()) return;
    await post('session/$_platform/google/link', {'idToken': ?token, 'googleAccessToken': ?accessToken}, sessionToken: this.accessToken);
  }
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
    cancelOAuth();
    final window = _windowFactory(); // Must open during the user gesture.
    final attempt = ++_oauthAttempt;
    final cancelled = Completer<void>();
    _oauthCancelled = cancelled;
    void cancel() { if (!cancelled.isCompleted) cancelled.complete(); }
    final monitor = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed || attempt != _oauthAttempt || window.closed) cancel();
    });
    Future<T> wait<T>(Future<T> future) async {
      final value = await Future.any<T>([future, cancelled.future.then<T>((_) => throw const _OAuthCancelled())]);
      if (cancelled.isCompleted || _disposed || attempt != _oauthAttempt || window.closed) throw const _OAuthCancelled();
      return value;
    }
    try {
      if (window.closed) throw const EmailAuthFailure('로그인 팝업을 허용해주세요.');
      await wait(_prepareTab());
      if (link && await wait(refresh()) == null) throw const EmailAuthFailure('다시 로그인해주세요.', status: 401);
      final proof = _random(32);
      final flow = await wait(post('session/$_platform/$provider/start', {'proof': proof, 'link': link}, sessionToken: accessToken));
      final url = flow['authorizeUrl'] as String;
      final target = Uri.parse(url);
      if (target.scheme != 'https' || !{'nid.naver.com', 'github.com', 'gitlab.com'}.contains(target.host)) throw const EmailAuthFailure('로그인 주소를 확인하지 못했습니다.');
      await wait(window.navigate(url));
      for (var i = 0; i < 300; i++) {
        final result = await wait(post('session/$_platform/$provider/finish', {'flow': flow['flow'] as String, 'proof': proof}, sessionToken: accessToken));
        if (result['pending'] != true) {
          if (!link) await _accept(result);
          return result;
        }
        await wait(Future<void>.delayed(const Duration(seconds: 2)));
      }
      throw const EmailAuthFailure('로그인 시간이 만료되었습니다. 다시 시도해주세요.');
    } on _OAuthCancelled { return null; }
    on EmailAuthFailure { rethrow; }
    catch (_) { throw const EmailAuthFailure('로그인 창을 열지 못했습니다. 브라우저의 팝업 설정을 확인해주세요.'); }
    finally {
      monitor.cancel(); window.close();
      if (identical(_oauthCancelled, cancelled)) _oauthCancelled = null;
    }
  }

  Future<Map<String, dynamic>> _login(String action, Map<String,String> credentials) async {
    await _prepareTab();
    final result = await post('session/$_platform/$action', credentials);
    await _accept(result);
    return result;
  }
  Future<void> _accept(Map<String, dynamic> result) async {
    if (_disposed) return;
    _authenticated = true;
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
  Future<void> clear() async { _authenticated = false; await store.clear();_tab = null;_refreshToken = null;_refreshId = null;accessToken = null; }
  void dispose() { _disposed = true;_peer.dispose();cancelOAuth();_client.close(); }
}

class _OAuthCancelled implements Exception { const _OAuthCancelled(); }

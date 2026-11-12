import 'dart:async';
import 'dart:convert';
import 'email_auth.dart';
import 'kakao_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth public client ID, never a client secret. Android uses the web client
/// as serverClientId; its own client is registered with package + signing SHA-1.
const defaultGoogleWebClientId = '905636849457-6ohbrffa2dalid9vbl479jat2rr7njoe.apps.googleusercontent.com';
const _configuredGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const googleWebClientId = _configuredGoogleWebClientId == ''
    ? defaultGoogleWebClientId : _configuredGoogleWebClientId;

class GoogleIdentity {
  const GoogleIdentity({required this.id, required this.email, required this.idToken, this.displayName});
  final String id, email;
  final String? idToken;
  final String? displayName;
  // Keep credentials in memory only. The future backend must verify this token
  // before issuing its own session; client-side identity is not API authorization.
}

abstract class GoogleAuthClient {
  bool get configured;
  Stream<GoogleIdentity?> get changes;
  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<void> dispose();
}

class SdkGoogleAuthClient implements GoogleAuthClient {
  final _sdk = GoogleSignIn.instance;
  final _changes = StreamController<GoogleIdentity?>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  @override
  bool get configured => googleWebClientId.isNotEmpty &&
      (kIsWeb || defaultTargetPlatform == TargetPlatform.android);
  @override
  Stream<GoogleIdentity?> get changes => _changes.stream;
  @override
  Future<void> initialize() async {
    await _sdk.initialize(clientId: kIsWeb ? googleWebClientId : null,
      serverClientId: kIsWeb ? null : googleWebClientId);
    _subscription = _sdk.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn(:final user):
          final token = user.authentication.idToken;
          if (token == null || token.isEmpty) {
            _changes.addError(StateError('Missing ID token'));
          } else {
            _changes.add(GoogleIdentity(id: user.id, email: user.email, idToken: token, displayName: user.displayName));
          }
        case GoogleSignInAuthenticationEventSignOut():
          _changes.add(null);
      }
    }, onError: (Object error) => _changes.addError(error));
    // Explicit sign-in only: logging out must not silently sign in again.
  }
  @override
  Future<void> signIn() async { await _sdk.authenticate(); }
  @override
  Future<void> signOut() async { await _sdk.signOut(); }
  @override
  Future<void> dispose() async { await _subscription?.cancel(); await _changes.close(); }
}

class GoogleAuthController extends ChangeNotifier {
  GoogleAuthController(this.client, {this.preferences, EmailAuthApi? emailApi, KakaoAuthClient? kakaoClient})
      : emailApi = emailApi ?? EmailAuthApi(), kakaoClient = kakaoClient ?? SdkKakaoAuthClient();
  final KakaoAuthClient kakaoClient;
  final EmailAuthApi emailApi;
  Future<void> Function()? onSessionEnding;
  Map<String, dynamic>? profile;
  Uint8List? profilePhoto;
  bool _googleLinkArmed = false;
  bool googleLinkBusy = false;
  int _profileReadGeneration = 0;
  Future<void> loadProfile() async {
    final readGeneration = ++_profileReadGeneration;
    final owner = identity?.id;
    if (!_emailSignedIn || owner == null) return;
    final data = await emailApi.profile('read');
    if (_disposed || identity?.id != owner || readGeneration != _profileReadGeneration) return;
    profile = data;
    try { profilePhoto = data['image'] is String ? base64Decode(data['image'] as String) : null; }
    catch (_) { profilePhoto = null; }
    identity = GoogleIdentity(id: owner, email: identity!.email, idToken: null, displayName: data['name'] as String?);
    _changed();
  }
  Future<void> prepareGoogleLink() async { _googleLinkArmed = true; await _initializeSdk(); }
  void endGoogleLink() { _googleLinkArmed = false; cancelAccountLink(); }
  Future<void> startGoogleLink() async { if (_googleLinkArmed && ready) { try { await client.signIn(); } catch (e) { _failure(e); } } }
  Future<void> _acceptGoogleLink(GoogleIdentity value) async {
    if (googleLinkBusy || value.idToken == null) return;
    final owner = identity?.id;
    googleLinkBusy = true; error = null; _changed();
    try { await emailApi.linkGoogle(value.idToken!, isCurrent: () => !_disposed && _googleLinkArmed && identity?.id == owner); await loadProfile(); }
    catch (e) { error = e is EmailAuthFailure ? e.message : 'Google 계정을 연결하지 못했습니다.'; }
    finally { googleLinkBusy = false; _changed(); }
  }
  bool _emailSignedIn = false;
  bool emailRestorePending = false;
  bool signingInWithBrowser = false;
  DateTime? _emailAccessExpires;
  bool get isEmailAccount => _emailSignedIn;
  Timer? _emailExpiry;
  static const rememberedAccountKey = 'weaver.test-login.v1';
  static const guestModeKey = 'weaver.guest-mode.v1';
  bool isGuest = false;
  bool get canUseCloud => !isGuest && identity != null &&
      _emailSignedIn && (_emailAccessExpires?.isAfter(DateTime.now()) ?? false);
  final SharedPreferences? preferences;
  final GoogleAuthClient client;
  GoogleIdentity? identity;
  bool ready = false, busy = false;
  String? error;
  bool _disposed = false, _loggingOut = false;
  int _generation = 0;
  Future<void> _sessionWrite = Future.value();
  StreamSubscription<GoogleIdentity?>? _subscription;
  Future<void>? _initializing;
  void _changed() { if (!_disposed) notifyListeners(); }
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    // Restore only a server-issued session; old local markers are not credentials.
    try {
      if (preferences?.getBool(guestModeKey) == true) {
        isGuest = true; _changed(); return;
      }
      try {
        final generation = _generation;
        final restored = await emailApi.restore();
        if (_disposed || isGuest || generation != _generation) return;
        if (restored != null) { _acceptEmail(restored); return; }
      } catch (_) {
        emailRestorePending = true;
        error = '로그인 상태를 복원하지 못했습니다. 연결 또는 기기 보안 저장소를 확인해주세요.';
      }
    } catch (_) { /* Invalid local markers require a real Google sign-in. */ }
    if (!_disposed && !isGuest) await _initializeSdk();
  }
  Future<void>? _sdkInitializing;
  Future<void> _initializeSdk() => _sdkInitializing ??= _startSdk();
  Future<void> _startSdk() async {
    if (!client.configured) { _changed(); return; }
    busy = true; _changed();
    _subscription = client.changes.listen((value) {
      if (value == null || _loggingOut || _disposed || isGuest) return;
      if (_emailSignedIn) { if (_googleLinkArmed) unawaited(_acceptGoogleLink(value)); return; }
      final generation = _generation;
      final write = _sessionWrite.catchError((Object _) {}).then((_) async {
        if (generation != _generation || _disposed || isGuest) return;
        try {
          if (value.idToken == null) throw const EmailAuthFailure('Google 계정으로 다시 로그인해주세요.');
          final data = await emailApi.loginGoogle(value.idToken!);
          if (generation != _generation || _disposed || isGuest) return;
          await preferences?.remove(rememberedAccountKey);
          await preferences?.remove(guestModeKey);
          _acceptEmail(data); busy = false; _changed();
        } catch (e) { error = e is EmailAuthFailure ? e.message : 'Google 서버 인증에 실패했습니다.'; busy = false; _changed(); }
      });
      _sessionWrite = write;
    }, onError: _failure);
    try { await client.initialize().timeout(const Duration(seconds: 10)); ready = true; }
    catch (_) { error = 'Google 로그인을 준비하지 못했습니다. 연결 및 OAuth 설정을 확인해 주세요.'; }
    finally { busy = false; _changed(); }
  }
  void _failure(Object exception) {
    busy = false;
    error = exception is GoogleSignInException && exception.code == GoogleSignInExceptionCode.canceled
        ? null : 'Google 로그인에 실패했습니다. 다시 시도해 주세요.';
    _changed();
  }
  Future<void> signIn() async {
    if (!ready || busy) return;
    busy = true; error = null; _changed();
    try { await client.signIn(); } catch (e) { _failure(e); }
    finally { busy = false; _changed(); }
  }
  Future<void> useGuest() async {
    if (identity != null || _loggingOut || isGuest) return;
    isGuest = true;
    emailApi.cancelOAuth();
    _generation++;
    try {
      await _sessionWrite;
      if (preferences != null) {
        if (!await preferences!.remove(rememberedAccountKey) ||
            !await preferences!.setBool(guestModeKey, true)) {
          throw StateError('Guest preference could not be saved');
        }
      }
      if (_disposed) return;
      isGuest = true; error = null; _changed();
    } catch (_) {
      isGuest = false;
      error = '비회원 사용 상태를 저장하지 못했습니다. 저장 공간을 확인해주세요.'; _changed();
    }
  }
  Future<void> leaveGuest() async {
    if (!isGuest) return;
    if (preferences != null && !await preferences!.remove(guestModeKey)) {
      throw StateError('Guest preference could not be removed');
    }
    isGuest = false; error = null; _changed();
    if (!ready && !_disposed) await _initializeSdk();
  }
  void _acceptEmail(Map<String, dynamic> data) {
    final changedAccount = identity?.id != 'email:${data['id']}';
    if (changedAccount) { profile = null; profilePhoto = null; }
    _emailSignedIn = true; isGuest = false; emailRestorePending = false;
    identity = GoogleIdentity(id: 'email:${data['id']}', email: data['email'] as String, idToken: null, displayName: data['name'] as String?);
    error = null;
    _emailAccessExpires = DateTime.now().add(Duration(seconds: data['expiresIn'] as int));
    _emailExpiry?.cancel();
    _emailExpiry = Timer(const Duration(minutes: 25), resumeEmailSession);
    if (changedAccount) unawaited(loadProfile().catchError((Object _) {}));
    _changed();
  }
  Future<void> resumeEmailSession() async {
    if (_disposed || _loggingOut || isGuest || (!_emailSignedIn && !emailRestorePending)) return;
    final generation = _generation;
    try {
      final data = emailRestorePending ? await emailApi.restore() : await emailApi.refresh();
      if (_disposed || generation != _generation) return;
      if (data == null) {
        try { await onSessionEnding?.call(); } catch (_) { /* Retain account-scoped recovery data, but end the expired session. */ }
        _emailSignedIn = false; identity = null; profile = null; profilePhoto = null; emailRestorePending = false;
        _emailExpiry?.cancel(); _changed();
        if (!ready) await _initializeSdk();
      } else { _acceptEmail(data); }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = '로그인 갱신에 연결이 필요합니다. 저장한 기기 인증 정보는 유지됩니다.';
      _emailExpiry?.cancel();
      _emailExpiry = Timer(const Duration(minutes: 1), resumeEmailSession);
      _changed();
    }
  }
  Future<void> signInWithEmail(String email, String password) async {
    final generation = ++_generation;
    final data = await emailApi.login(email, password);
    if (_disposed || generation != _generation || isGuest) {
      try { await emailApi.logout(); } catch (_) {}
      return;
    }
    await _sessionWrite;
    await preferences?.remove(rememberedAccountKey);
    await preferences?.remove(guestModeKey);
    if (_disposed || generation != _generation) return;
    _acceptEmail(data);
  }
  Future<void> signInWithKakao() async {
    if (busy || isGuest) return;
    final generation = ++_generation;
    busy = true; error = null; _changed();
    try {
      final token = await kakaoClient.accessToken();
      if (token == null || _disposed || generation != _generation) return;
      final data = await emailApi.loginKakao(token);
      if (_disposed || generation != _generation) {
        try { await emailApi.logout(); } catch (_) {}
        return;
      }
      await _sessionWrite;
      await preferences?.remove(rememberedAccountKey);
      await preferences?.remove(guestModeKey);
      if (!_disposed && generation == _generation) _acceptEmail(data);
    } on EmailAuthFailure catch (e) { error = e.message; }
    catch (_) { error = '카카오 로그인에 실패했습니다. 다시 시도해주세요.'; }
    finally { busy = false; _changed(); }
  }
  void cancelBrowserSignIn() {
    emailApi.cancelOAuth(); _generation++; signingInWithBrowser = false; error = '로그인 요청을 취소하고 있습니다.'; _changed();
  }
  Future<void> signInWithBrowser(String provider) async {
    if (busy || isGuest) return;
    final generation = ++_generation;
    busy = true; signingInWithBrowser = true; error = null; _changed();
    try {
      final data = await emailApi.loginBrowser(provider);
      if (data == null) return;
      if (_disposed || generation != _generation) {
        try { await emailApi.logout(); } catch (_) {}
        return;
      }
      await _sessionWrite;
      await preferences?.remove(rememberedAccountKey);
      await preferences?.remove(guestModeKey);
      if (!_disposed && generation == _generation) _acceptEmail(data);
    } on EmailAuthFailure catch (e) { error = e.message; }
    catch (_) { error = '로그인에 실패했습니다. 다시 시도해주세요.'; }
    finally { busy = false; signingInWithBrowser = false; _changed(); }
  }
  Completer<bool>? _linkCancelled;
  void cancelAccountLink() {
    emailApi.cancelOAuth();
    final pending = _linkCancelled;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }
  Future<bool> _link(Future<bool> Function(Completer<bool>) action) async {
    if (!_emailSignedIn || isGuest) throw const EmailAuthFailure('먼저 로그인해주세요.');
    cancelAccountLink();
    final cancelled = Completer<bool>();
    _linkCancelled = cancelled;
    try { return await Future.any([action(cancelled), cancelled.future]); }
    finally { if (identical(_linkCancelled, cancelled)) _linkCancelled = null; }
  }
  Future<bool> linkBrowser(String provider) => _link((_) async =>
    await emailApi.loginBrowser(provider, link: true) != null);
  Future<bool> linkKakao() => _link((cancelled) async {
    final token = await kakaoClient.accessToken();
    if (token == null || cancelled.isCompleted || _disposed) return false;
    await emailApi.linkKakao(token);
    return !cancelled.isCompleted;
  });
  Future<void> signOut({bool allDevices = false}) async {
    if (_loggingOut) return;
    _loggingOut = true; _generation++; busy = true; _changed();
    try {
      if (_emailSignedIn) await emailApi.logout(all: allDevices);
      try { await onSessionEnding?.call(); } catch (_) { /* Cleanup failure must not keep a revoked session active. */ }
      await _sessionWrite;
      if (preferences != null && !await preferences!.remove(rememberedAccountKey)) {
        throw StateError('Account removal failed');
      }
      _emailSignedIn = false; _emailAccessExpires = null; _emailExpiry?.cancel();
      identity = null; profile = null; profilePhoto = null; isGuest = true; await preferences?.setBool(guestModeKey, true); error = null; _changed();
      // Local logout must work even if Google's network/provider is unavailable.
      if (ready) {
        try { await client.signOut().timeout(const Duration(seconds: 5)); } catch (_) {}
      }
    } catch (_) { error = '서버의 세션을 폐기하지 못했습니다. 연결을 확인하고 다시 로그아웃해주세요.'; }
    finally { _loggingOut = false; busy = false; _changed(); }
    if (identity == null && !ready && !_disposed) await _initializeSdk();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelAccountLink();
    _emailExpiry?.cancel();
    emailApi.dispose();
    unawaited(_subscription?.cancel());
    unawaited(client.dispose());
    super.dispose();
  }
}

class GoogleAuthScope extends InheritedNotifier<GoogleAuthController> {
  const GoogleAuthScope({super.key, required GoogleAuthController controller, required super.child}) : super(notifier: controller);
  static GoogleAuthController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GoogleAuthScope>()?.notifier;
}

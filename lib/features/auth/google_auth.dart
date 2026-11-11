import 'dart:async';
import 'email_auth.dart';
import 'dart:convert';
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
  const GoogleIdentity({required this.id, required this.email, required this.idToken});
  final String id, email;
  final String? idToken;
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
            _changes.add(GoogleIdentity(id: user.id, email: user.email, idToken: token));
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
  GoogleAuthController(this.client, {this.preferences, EmailAuthApi? emailApi}) : emailApi = emailApi ?? EmailAuthApi();
  final EmailAuthApi emailApi;
  String? _emailSessionToken;
  Timer? _emailExpiry;
  static const rememberedAccountKey = 'weaver.test-login.v1';
  static const guestModeKey = 'weaver.guest-mode.v1';
  bool isGuest = false;
  bool get canUseCloud => !isGuest && identity != null;
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
    // Deliberately a non-expiring test account marker, not an OAuth session.
    // Do not persist ID tokens or ask Google to refresh this local marker.
    try {
      if (preferences?.getBool(guestModeKey) == true) {
        isGuest = true; _changed(); return;
      }
      final raw = preferences?.getString(rememberedAccountKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is Map && data['id'] is String && (data['id'] as String).isNotEmpty &&
            data['email'] is String && (data['email'] as String).isNotEmpty) {
          identity = GoogleIdentity(id: data['id'] as String, email: data['email'] as String, idToken: null);
          _changed();
          return;
        }
      }
    } catch (_) { /* Invalid local markers require a real Google sign-in. */ }
    await _initializeSdk();
  }
  Future<void>? _sdkInitializing;
  Future<void> _initializeSdk() => _sdkInitializing ??= _startSdk();
  Future<void> _startSdk() async {
    if (!client.configured) { _changed(); return; }
    busy = true; _changed();
    _subscription = client.changes.listen((value) {
      if (value == null || _loggingOut || _disposed || _emailSessionToken != null || isGuest) return;
      final generation = _generation;
      final write = _sessionWrite.catchError((Object _) {}).then((_) async {
        if (generation != _generation || _disposed || isGuest) return;
        try {
          if (preferences != null && !await preferences!.setString(rememberedAccountKey,
              jsonEncode({'id': value.id, 'email': value.email}))) {
            throw StateError('Account persistence failed');
          }
          if (generation != _generation || _disposed || isGuest) return;
          identity = value; error = null; busy = false; _changed();
        } catch (_) {
          if (generation == _generation && !_disposed) {
            error = '로그인 상태를 기기에 저장하지 못했습니다. 다시 시도해주세요.';
            busy = false; _changed();
          }
        }
      });
      _sessionWrite = write;
    }, onError: _failure);
    try { await client.initialize(); ready = true; }
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
  Future<void> signInWithEmail(String email, String password) async {
    final data = await emailApi.post('login', {'email': email, 'password': password});
    _generation++;
    await _sessionWrite;
    await preferences?.remove(rememberedAccountKey);
    await preferences?.remove(guestModeKey);
    if (_disposed) return;
    isGuest = false;
    _emailSessionToken = data['sessionToken'] as String;
    identity = GoogleIdentity(id: 'email:${data['id']}', email: data['email'] as String, idToken: null);
    error = null;
    _emailExpiry?.cancel();
    _emailExpiry = Timer(Duration(seconds: data['expiresIn'] as int), () {
      _emailSessionToken = null; identity = null; _changed();
    });
    _changed();
  }
  Future<void> signOut() async {
    if (_loggingOut) return;
    _loggingOut = true; _generation++; busy = true; _changed();
    try {
      await _sessionWrite;
      if (preferences != null && !await preferences!.remove(rememberedAccountKey)) {
        throw StateError('Account removal failed');
      }
      final session = _emailSessionToken;
      _emailSessionToken = null; _emailExpiry?.cancel();
      identity = null; error = null; _changed();
      if (session != null) {
        try { await emailApi.post('logout', {}, sessionToken: session); } catch (_) {}
      }
      // Local logout must work even if Google's network/provider is unavailable.
      if (ready) {
        try { await client.signOut().timeout(const Duration(seconds: 5)); } catch (_) {}
      }
    } catch (_) { error = '로그인 상태를 지우지 못했습니다. 다시 로그아웃해주세요.'; }
    finally { _loggingOut = false; busy = false; _changed(); }
    if (identity == null && !ready && !_disposed) await _initializeSdk();
  }

  @override
  void dispose() {
    _disposed = true;
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

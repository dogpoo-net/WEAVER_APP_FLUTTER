import 'dart:async';
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
  final String id, email, idToken;
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
    // A lightweight attempt can return null on web; events are authoritative.
    final attempt = _sdk.attemptLightweightAuthentication();
    if (attempt != null) unawaited(attempt.then<void>((_) {}, onError: (Object _) {}));
  }
  @override
  Future<void> signIn() async { await _sdk.authenticate(); }
  @override
  Future<void> signOut() async { await _sdk.signOut(); }
  @override
  Future<void> dispose() async { await _subscription?.cancel(); await _changes.close(); }
}

class GoogleAuthController extends ChangeNotifier {
  GoogleAuthController(this.client);
  final GoogleAuthClient client;
  GoogleIdentity? identity;
  bool ready = false, busy = false;
  String? error;
  bool _disposed = false;
  StreamSubscription<GoogleIdentity?>? _subscription;
  Future<void>? _initializing;
  void _changed() { if (!_disposed) notifyListeners(); }
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!client.configured) { _changed(); return; }
    busy = true; _changed();
    _subscription = client.changes.listen((value) {
      identity = value; error = null; busy = false; _changed();
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
  Future<void> signOut() async {
    if (busy) return;
    busy = true; _changed();
    try { await client.signOut(); identity = null; error = null; }
    catch (_) { error = '로그아웃하지 못했습니다. 다시 시도해 주세요.'; }
    finally { busy = false; _changed(); }
  }
  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(client.dispose());
    super.dispose();
  }
}

class GoogleAuthScope extends InheritedNotifier<GoogleAuthController> {
  const GoogleAuthScope({super.key, required GoogleAuthController controller, required super.child}) : super(notifier: controller);
  static GoogleAuthController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GoogleAuthScope>()?.notifier;
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/inbox/thought_settings.dart';
import 'login_presentation_test.dart' show NoGoogle;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/oauth_window_handle.dart';
import 'support/memory_session_store.dart';

class FakeWindow implements OAuthWindowHandle {
  @override bool closed = false;
  @override Future<void> navigate(String url) async {}
  @override void close() { closed = true; }
}
http.Response response(Map<String, Object?> value) => http.Response(jsonEncode(value), 200);
void main() {
  testWidgets('Settings unlocks after closing an account-link popup', (tester) async {
    final window = FakeWindow();
    final pending = Completer<http.Response>();
    final api = EmailAuthApi(store: MemorySessionStore(isWeb: true), oauthWindowFactory: () => window,
      client: MockClient((request) async => request.url.path.endsWith('/start') ? pending.future :
        response({'id': 'account', 'email': 'account@example.com', 'expiresIn': 1800})));
    final auth = GoogleAuthController(NoGoogle(), emailApi: api);
    await auth.signInWithEmail('account@example.com', 'password');
    await tester.pumpWidget(GoogleAuthScope(controller: auth, child: MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: TextButton(onPressed: () => showThoughtSettings(context, null), child: const Text('settings')))))));
    await tester.tap(find.text('settings')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GitHub 계정 연결'));
    await tester.tap(find.text('GitHub 계정 연결')); await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    window.closed = true; await tester.pump(const Duration(milliseconds: 250)); await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final close = tester.widget<IconButton>(find.byKey(const ValueKey('close-settings')));
    expect(close.onPressed, isNotNull);
    pending.complete(response({'flow': 'late', 'authorizeUrl': 'https://github.com/login/oauth/authorize'}));
    await tester.pump(); await tester.pumpWidget(const SizedBox()); auth.dispose();
  });
  for (final phase in ['start', 'finish', 'refresh']) {
    test('Closing popup releases pending $phase and ignores late responses', () async {
      final window = FakeWindow();
      final pending = Completer<http.Response>();
      final reached = Completer<void>();
      final store = MemorySessionStore(isWeb: true);
      final api = EmailAuthApi(store: store, oauthWindowFactory: () => window,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/$phase')) {
            reached.complete(); return pending.future;
          }
          return response({'flow': 'test-flow', 'authorizeUrl': 'https://github.com/login/oauth/authorize'});
        }));
      final result = api.loginBrowser('github', link: phase == 'refresh');
      await reached.future;
      window.closed = true;
      expect(await result.timeout(const Duration(seconds: 2)), isNull);
      pending.complete(response({'id': 'late', 'email': 'late@example.com'}));
      await Future<void>.delayed(Duration.zero);
      expect(api.accessToken, isNull);
      api.dispose();
    });
  }
  test('Explicit cancellation releases request and permits a new attempt', () async {
    final first = Completer<http.Response>();
    final reached = Completer<void>();
    var starts = 0;
    final api = EmailAuthApi(store: MemorySessionStore(isWeb: true), oauthWindowFactory: FakeWindow.new,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/start')) {
          if (++starts == 1) { reached.complete(); return first.future; }
          return response({'flow': 'new-flow', 'authorizeUrl': 'https://gitlab.com/oauth/authorize'});
        }
        return response({'id': 'current', 'email': 'current@example.com', 'expiresIn': 1800});
      }));
    final old = api.loginBrowser('gitlab');
    await reached.future; api.cancelOAuth();
    expect(await old.timeout(const Duration(seconds: 1)), isNull);
    expect((await api.loginBrowser('gitlab'))?['id'], 'current');
    first.complete(response({'flow': 'stale-flow', 'authorizeUrl': 'https://gitlab.com/oauth/authorize'}));
    await Future<void>.delayed(Duration.zero); api.dispose();
  });
}

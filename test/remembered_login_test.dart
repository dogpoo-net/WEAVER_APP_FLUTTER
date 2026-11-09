import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/thought_settings.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/auth/login_page.dart';
import 'package:weaver/main.dart';

class RememberedClient implements GoogleAuthClient {
  final events = StreamController<GoogleIdentity?>.broadcast();
  int initialized = 0, signedOut = 0;
  bool failLogout = false;
  @override
  bool get configured => true;
  @override
  Stream<GoogleIdentity?> get changes => events.stream;
  @override
  Future<void> initialize() async { initialized++; }
  @override
  Future<void> signIn() async {
    events.add(const GoogleIdentity(id: 'google-user', email: 'user@example.com', idToken: 'do-not-store-token'));
  }
  @override
  Future<void> signOut() async {
    signedOut++;
    if (failLogout) throw StateError('Offline');
    events.add(null);
  }
  @override
  Future<void> dispose() async { await events.close(); }
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('remember account across restart; settings logout requires sign-in again', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = WorkspaceStorage(prefs);
    final first = RememberedClient();
    await tester.pumpWidget(MyApp(storage: storage, authClient: first));
    await tester.pumpAndSettle();
    // Inject the same SDK success event on all test platforms, including web.
    await first.signIn(); await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    final raw = prefs.getString(GoogleAuthController.rememberedAccountKey)!;
    expect(raw, contains('user@example.com'));
    expect(raw, isNot(contains('do-not-store-token')));
    await tester.pumpWidget(const SizedBox());
    final second = RememberedClient();
    await tester.pumpWidget(MyApp(storage: storage, authClient: second));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    expect(second.initialized, 0);
    final context = tester.element(find.byType(InboxPage));
    expect(GoogleAuthScope.maybeOf(context)!.identity!.idToken, isNull);
    unawaited(showThoughtSettings(context, prefs));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃')); await tester.pumpAndSettle();
    expect(prefs.getString(GoogleAuthController.rememberedAccountKey), isNull);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(InboxPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MyApp(storage: storage, authClient: RememberedClient()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  }, skip: kIsWeb);
  test('restart restores account without contacting Google and logout removes it', () async {
    final prefs = await SharedPreferences.getInstance();
    final original = GoogleAuthController(RememberedClient(), preferences: prefs);
    await original.initialize(); await original.signIn();
    await Future<void>.delayed(Duration.zero);
    expect(original.identity?.id, 'google-user');
    original.dispose();
    final client = RememberedClient();
    final restored = GoogleAuthController(client, preferences: prefs);
    await restored.initialize();
    expect(restored.identity?.email, 'user@example.com');
    expect(restored.identity?.idToken, isNull);
    expect(client.initialized, 0);
    await restored.signOut();
    expect(restored.identity, isNull);
    expect(prefs.getString(GoogleAuthController.rememberedAccountKey), isNull);
    restored.dispose();
    final next = GoogleAuthController(RememberedClient(), preferences: prefs);
    await next.initialize(); expect(next.identity, isNull); next.dispose();
  });
  test('provider errors and expiry cannot clear the test marker; explicit logout can', () async {
    final prefs = await SharedPreferences.getInstance();
    final client = RememberedClient()..failLogout = true;
    final auth = GoogleAuthController(client, preferences: prefs);
    await auth.initialize();
    await auth.signIn(); await Future<void>.delayed(Duration.zero);
    client.events.add(null); await Future<void>.delayed(Duration.zero);
    expect(auth.identity?.email, 'user@example.com');
    await auth.signOut();
    expect(auth.identity, isNull);
    expect(prefs.getString(GoogleAuthController.rememberedAccountKey), isNull);
    auth.dispose();
  });
}

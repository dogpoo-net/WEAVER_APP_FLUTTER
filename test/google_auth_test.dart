import 'package:weaver/features/auth/email_auth.dart';
import 'support/memory_session_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/login_page.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

class FakeGoogleClient implements GoogleAuthClient {
  FakeGoogleClient({this.configured = true});
  @override
  final bool configured;
  final events = StreamController<GoogleIdentity?>.broadcast();
  bool fail = false;
  @override
  Stream<GoogleIdentity?> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn() async {
    if (fail) throw StateError('Network failure');
    events.add(const GoogleIdentity(id: 'test-user', email: 'test@example.com', idToken: 'test-token'));
  }
  @override
  Future<void> signOut() async { events.add(null); }
  @override
  Future<void> dispose() async { await events.close(); }
}
void main() {
  testWidgets('missing OAuth config gates workspace without modifying local data', (tester) async {
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: 'existing-data'});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(emailApi: EmailAuthApi(store: MemorySessionStore()), storage: storage, authClient: FakeGoogleClient(configured: false)));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(InboxPage), findsNothing);
    expect(storage.read(), 'existing-data');
  });
  testWidgets('sign in enters workspace and sign out removes nested routes', (tester) async {
    final client = FakeGoogleClient();
    await tester.pumpWidget(MyApp(emailApi: EmailAuthApi(store: MemorySessionStore()), authClient: client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google로 로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    final context = tester.element(find.byType(InboxPage));
    final auth = GoogleAuthScope.maybeOf(context)!;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Private route'))));
    await tester.pumpAndSettle();
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Private route'), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(InboxPage), findsNothing);
  });
  testWidgets('failed sign in does not unlock workspace and can retry', (tester) async {
    final client = FakeGoogleClient()..fail = true;
    await tester.pumpWidget(MyApp(emailApi: EmailAuthApi(store: MemorySessionStore()), authClient: client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google로 로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsNothing);
    expect(find.textContaining('로그인에 실패'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('Google로 로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
  });
}

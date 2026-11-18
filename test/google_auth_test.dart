import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException, GoogleSignInExceptionCode;
import 'support/test_server_auth.dart';
import 'support/memory_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
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
  Object? failure;
  @override
  Stream<GoogleIdentity?> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signIn() async {
    if(failure!=null)throw failure!;
    if (fail) throw StateError('Network failure');
    events.add(const GoogleIdentity(id: 'test-user', email: 'test@example.com', idToken: 'test-token'));
  }
  @override
  Future<void> signOut() async { events.add(null); }
  @override
  Future<void> dispose() async { await events.close(); }
}
class SlowGoogleClient extends FakeGoogleClient {
  final initialization = Completer<void>();
  @override
  Future<void> initialize() => initialization.future;
}
class PendingGoogleApi extends EmailAuthApi {
 PendingGoogleApi():super(store:MemorySessionStore(isWeb:false));
 final entered=Completer<void>(), release=Completer<Map<String,dynamic>>();
 @override Future<Map<String,dynamic>?> restore()async=>null;
 @override Future<Map<String,dynamic>> loginGoogle(String? token,{String? accessToken}){entered.complete();return release.future;}
 @override Future<Map<String,dynamic>> profile(String action, [Map<String,Object?> body=const {}])async=>{};
}
void main() {
 test('Google progress continues until server session exchange finishes',()async{
  final client=FakeGoogleClient(),api=PendingGoogleApi();
  final auth=GoogleAuthController(client,emailApi:api);await auth.initialize();
  await Future<void>.delayed(Duration.zero);expect(auth.ready,isTrue);
  final login=auth.signIn();await api.entered.future;await Future<void>.delayed(Duration.zero);
  expect(auth.busy,isTrue);expect(auth.identity,isNull);
  api.release.complete({'id':'user','email':'user@example.com','expiresIn':1800});
  await login;expect(auth.busy,isFalse);expect(auth.identity?.id,'email:user');
  auth.dispose();
 });
 testWidgets('SDK cancellation is visible instead of silently returning to login',(tester)async{
  final client=FakeGoogleClient()..failure=const GoogleSignInException(code:GoogleSignInExceptionCode.canceled);
  await tester.pumpWidget(MyApp(emailApi:testServerAuth(),authClient:client));await tester.pumpAndSettle();
  await tester.tap(find.text('Google로 로그인'));await tester.pumpAndSettle();
  expect(find.textContaining('Google 로그인이 완료되지 않았습니다.'),findsOneWidget);
  expect(find.byType(LoginPage),findsOneWidget);await tester.pumpWidget(const SizedBox());
 });

  testWidgets('slow Google setup does not block login page or guest entry', (tester) async {
    final client = SlowGoogleClient();
    await tester.pumpWidget(MyApp(emailApi: testServerAuth(), authClient: client));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoginPage), findsOneWidget);
    final auth = GoogleAuthScope.maybeOf(tester.element(find.byType(LoginPage)))!;
    expect(auth.busy, isFalse);
    expect(auth.ready, isFalse);
    await tester.tap(find.text('비회원으로 사용하기'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    client.initialization.complete();
    await tester.pump();
    expect(auth.isGuest, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('slow session restore releases startup and retains native credentials', (tester) async {
    final pending = Completer<http.Response>();
    final store = MemorySessionStore()..value = '{"refreshToken":"saved-token"}';
    final api = EmailAuthApi(store: store, client: MockClient((_) => pending.future));
    await tester.pumpWidget(MyApp(emailApi: api, authClient: FakeGoogleClient()));
    await tester.pump();
    expect(find.byType(LoginPage), findsNothing);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(store.value, contains('saved-token'));
    expect(find.text('로그인 상태 다시 확인'), findsOneWidget);
    // A response arriving after the timeout must not accept a stale session.
    pending.complete(http.Response('{"refreshToken":"late-token","accessToken":"late"}', 200));
    await tester.pump();
    expect(store.value, contains('saved-token'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing OAuth config gates workspace without modifying local data', (tester) async {
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: 'existing-data'});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(emailApi: testServerAuth(), storage: storage, authClient: FakeGoogleClient(configured: false)));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(InboxPage), findsNothing);
    expect(OwnedWorkspaces(storage).scope('quarantine').read(), 'existing-data');
    expect(storage.read(), isNull);
  });
  testWidgets('sign in enters workspace and sign out removes nested routes', (tester) async {
    final client = FakeGoogleClient();
    await tester.pumpWidget(MyApp(emailApi: testServerAuth(), authClient: client));
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
    expect(auth.isGuest, isFalse);
  });
  testWidgets('failed sign in does not unlock workspace and can retry', (tester) async {
    final client = FakeGoogleClient()..fail = true;
    await tester.pumpWidget(MyApp(emailApi: testServerAuth(), authClient: client));
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

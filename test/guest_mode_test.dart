import 'support/memory_session_store.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/login_page.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/thought_settings.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/main.dart';

class GuestGoogleClient implements GoogleAuthClient {
  int initializations = 0;
  final events = StreamController<GoogleIdentity?>.broadcast();
  @override bool get configured => true;
  @override Stream<GoogleIdentity?> get changes => events.stream;
  @override Future<void> initialize() async { initializations++; }
  @override Future<void> signIn() async {}
  @override Future<void> signOut() async {}
  @override Future<void> dispose() async { await events.close(); }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Guest entry blocks cloud actions and retains data when opening login', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = WorkspaceStorage(prefs);
    final owned=OwnedWorkspaces(storage);await owned.initialize();final guest=await owned.guest();
    await guest.write(WorkspaceSnapshot.encode([Note('비회원의 로컬 기록')]));
    final before = guest.read();
    await tester.pumpWidget(MyApp(emailApi: EmailAuthApi(store: MemorySessionStore()), storage: storage, authClient: GuestGoogleClient()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('비회원으로 사용하기'));
    await tester.tap(find.text('비회원으로 사용하기'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    final context = tester.element(find.byType(InboxPage));
    final auth = GoogleAuthScope.maybeOf(context)!;
    expect(auth.isGuest, isTrue);expect(auth.identity, isNull);expect(auth.canUseCloud, isFalse);
    var transfers = 0;
    unawaited(showThoughtSettings(context, prefs, onUpload: () async { transfers++; }, onDownload: () async { transfers++; }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동기화 관리'));await tester.pumpAndSettle();
    for (final label in ['변경사항 동기화','서버 변경 불러오기']) {
      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, label));
      expect(tile.enabled, isFalse);expect(tile.onTap, isNull);
    }
    expect(transfers, 0);
    await tester.ensureVisible(find.text('로그인 / 회원가입'));
    await tester.tap(find.text('로그인 / 회원가입'));await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(guest.read(), before);
    expect(prefs.getBool(GoogleAuthController.guestModeKey), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('Guest survives restart without initializing a provider and ignores late Google events', () async {
    final prefs = await SharedPreferences.getInstance();
    final firstClient = GuestGoogleClient();
    final first = GoogleAuthController(firstClient, preferences: prefs);
    await first.initialize();await first.useGuest();
    firstClient.events.add(const GoogleIdentity(id:'late',email:'late@example.com',idToken:'token'));
    await Future<void>.delayed(Duration.zero);
    expect(first.identity,isNull);expect(first.canUseCloud,isFalse);
    first.dispose();
    final secondClient = GuestGoogleClient();
    final second = GoogleAuthController(secondClient, preferences:prefs);
    await second.initialize();
    expect(second.isGuest,isTrue);expect(second.canUseCloud,isFalse);expect(secondClient.initializations,0);
    second.dispose();
  });

  test('Email authentication alone never reclassifies guest data as account data', () async {
    final prefs=await SharedPreferences.getInstance();final owned=OwnedWorkspaces(WorkspaceStorage(prefs));await owned.initialize();final guest=await owned.guest();
    final original=WorkspaceSnapshot.encode([Note('회원가입 전 작성한 생각')]);await guest.write(original);
    final auth=GoogleAuthController(GuestGoogleClient(),preferences:prefs,emailApi:EmailAuthApi(store:MemorySessionStore(),client:MockClient((_)async=>http.Response(jsonEncode({'id':'user','email':'guest@example.com','refreshToken':'refresh','accessToken':'access','expiresIn':1800}),200))));
    await auth.signInWithEmail('guest@example.com','password');
    expect(guest.read(),original);expect(owned.scope(auth.identity!.id).read(),isNull);
    auth.dispose();
  });
}

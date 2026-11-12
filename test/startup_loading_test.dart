import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/auth/login_page.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/all_thoughts_page.dart';
import 'package:weaver/features/inbox/desktop_menu_frame.dart';
import 'google_auth_test.dart' show FakeGoogleClient;
import 'support/memory_session_store.dart';

class DelayedSession extends EmailAuthApi {
  DelayedSession() : super(store: MemorySessionStore());
  final result = Completer<Map<String, dynamic>?>();
  @override Future<Map<String, dynamic>?> restore() => result.future;
  @override Future<Map<String, dynamic>> profile(String action, [Map<String, Object?> body = const {}]) async => {};
}
void main() {
  for (final authenticated in [true, false]) {
    testWidgets('restoring session hides login; authenticated=$authenticated', (tester) async {
      final api = DelayedSession();
      await tester.pumpWidget(MyApp(emailApi: api, authClient: FakeGoogleClient(configured: false)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      api.result.complete(authenticated ? {'id':'server-user','email':'user@example.com','name':'Test','expiresIn':1800} : null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), authenticated ? findsNothing : findsOneWidget);
      expect(find.byType(InboxPage), authenticated ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('pinned menu stays in the same place during server read', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final owner = Object();
    desktopMenu.visible = true;
    desktopMenu.attach(owner, (_) => const SizedBox(width:220, child: Text('Pinned menu')), () {}, () => true);
    final read = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: AllThoughtsPage(notes: const [], onRefresh: () => read.future)));
    final before = tester.getTopLeft(find.text('Pinned menu'));
    await tester.pump();
    expect(find.text('서버 변경을 불러오는 중입니다.'), findsOneWidget);
    expect(find.text('Pinned menu'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Pinned menu')), before);
    read.complete();
    await tester.pumpAndSettle();
    expect(find.text('Pinned menu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    desktopMenu.detach(owner);
  });
}

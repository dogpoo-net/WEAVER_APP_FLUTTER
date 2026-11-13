import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/owned_workspace.dart';
import 'package:weaver/features/sync/sharing_pages.dart';
import 'package:weaver/features/sync/readonly_workspace.dart';

import 'support/memory_session_store.dart';

class SharingApi extends EmailAuthApi {
  SharingApi() : super(store: MemorySessionStore(isWeb: true));
  final calls = <String>[];
  Map<String, Object?>? last;
  @override
  Future<Map<String, dynamic>> workspace(
    String action,
    Map<String, Object?> body,
  ) async {
    calls.add(action);
    last = body;
    return switch (action) {
      'read' => {'revision': 0, 'changes': []},
      'members' => {
        'members': [
          {
            'userId': 'owner',
            'name': 'Owner',
            'email': 'owner@example.com',
            'role': 'owner',
          },
        ],
        'invitations': [],
      },
      'catalog' => {
        'workspaces': [],
        'invitations': [
          {'id': 'invite', 'name': 'Team', 'role': 'viewer'},
        ],
      },
      'accept' => {'workspaceId': 'shared'},
      'history' => {
        'versions': [
          {
            'version': 2,
            'actorName': 'Editor',
            'action': 'unlocked_edit',
            'createdAt': '2026-11-11T12:00:00Z',
            'added': 2,
            'removed': 1,
            'changes': jsonEncode([
              {'operation': 'equal', 'text': '본문\n'},
              {'operation': 'delete', 'text': '전', 'beforeLine': 2},
              {'operation': 'insert', 'text': '추가', 'afterLine': 2},
            ]),
            'afterText': '본문 추가',
          },
        ],
      },
      _ => {},
    };
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Shared workspace id is explicit and read-only sync never sends a write',
    () async {
      final api = SharingApi();
      final storage = WorkspaceStorage(
        await SharedPreferences.getInstance(),
        owner: 'account@workspace:shared',
      );
      final sync = WorkspaceSync(
        storage,
        api,
        workspaceId: 'shared',
        readOnly: true,
        isCurrent: () => true,
      );
      await sync.initialize();
      expect(api.last!['workspaceId'], 'shared');
      await expectLater(
        sync.request('save', {}),
        throwsA(isA<EmailAuthFailure>()),
      );
      expect(api.calls, isNot(contains('save')));
      sync.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'Invite management is owner-only and accepting preserves workspace selection callback',
    (tester) async {
      final api = SharingApi();
      final sync = WorkspaceSync(
        WorkspaceStorage(
          await SharedPreferences.getInstance(),
          owner: 'viewer',
        ),
        api,
        workspaceId: 'shared',
        readOnly: true,
        isCurrent: () => true,
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: SharingPage(
            sync: sync,
            role: 'viewer',
            onAccepted: (id) async {
              selected = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('초대메일 보내기'), findsNothing);
      expect(find.textContaining('소유자 포함 편집자 2명'), findsOneWidget);
      await tester.tap(find.text('수락'));
      await tester.pumpAndSettle();
      expect(selected, 'shared');
      sync.dispose();
      api.dispose();
    },
  );
  testWidgets('History shows author, additions/deletions and changed lines', (
    tester,
  ) async {
    final api = SharingApi();
    final sync = WorkspaceSync(
      WorkspaceStorage(await SharedPreferences.getInstance(), owner: 'a'),
      api,
      workspaceId: 'shared',
      isCurrent: () => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentHistoryPage(sync: sync, documentId: 'doc'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('버전 2 · Editor'), findsOneWidget);
    expect(find.textContaining('+2자 / −1자'), findsOneWidget);
    await tester.tap(find.text('버전 2 · Editor'));
    await tester.pumpAndSettle();
    expect(find.text('추가 · 2행부터'), findsOneWidget);
    expect(find.byTooltip('이 버전은 잠금 해제 후 저장했습니다.'), findsOneWidget);
    await tester.tap(find.text('이 버전 전체 보기')); await tester.pumpAndSettle();
    expect(find.text('버전 2 전체 변경 비교'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('전', findRichText: true)), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('추가', findRichText: true)), findsOneWidget);
    await tester.tap(find.text('닫기')); await tester.pumpAndSettle();
    expect(api.last!['workspaceId'], 'shared');
    sync.dispose();
    api.dispose();
  });
  testWidgets('Viewer interface exposes no compose or save input', (
    tester,
  ) async {
    final storage = WorkspaceStorage(
      await SharedPreferences.getInstance(),
      owner: 'viewer',
    );
    await storage.write(
      jsonEncode({
        'version': 1,
        'colors': {},
        'elements': [],
        'trash': [],
        'notes': [],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReadonlyWorkspace(storage: storage, onHistory: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('저장'), findsNothing);
    expect(find.text('읽기 전용 워크스페이스'), findsOneWidget);
  });
}

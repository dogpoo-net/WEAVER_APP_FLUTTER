import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/main.dart';

void main() {
 setUp(() => SharedPreferences.setMockInitialValues({}));
 testWidgets('interrupted new document reopens from its local notification', (tester) async {
   final storage = WorkspaceStorage(await SharedPreferences.getInstance());
   await storage.writeDocumentDraft('new-document', {'text':'복구할 본문','links':[],'tags':[]});
   await tester.pumpWidget(MyApp(requireLogin:false,storage:storage));
   await tester.pumpAndSettle();
   await tester.tap(find.byKey(const ValueKey('notification-badge')));
   await tester.pumpAndSettle();
   await tester.tap(find.text('작성 중인 문서가 있습니다.'));
   await tester.pumpAndSettle();
   await tester.pump(const Duration(milliseconds: 300));
   await tester.pumpAndSettle();
   expect(tester.widget<TextField>(find.byKey(const ValueKey('project-document'))).controller!.text,'복구할 본문');
   await tester.pageBack(); await tester.pumpAndSettle();
   await tester.tap(find.text('나가기')); await tester.pumpAndSettle();
   expect(storage.documentDraft('new-document'), isNull);
   expect(find.byKey(const ValueKey('notification-badge')), findsNothing);
   await tester.pumpWidget(const SizedBox());
 });
}

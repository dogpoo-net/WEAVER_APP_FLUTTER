import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';

void main() {
  testWidgets('desktop search stays at the top when result height changes', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = List.generate(15, (i) => Note('저장된 문단 $i')
      ..paragraphs = [Paragraph('저장된 문단 $i', ParagraphRole.body)]);
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode(notes)});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('note-search'));
    final before = tester.getRect(search);
    await tester.enterText(search, '없는 검색어');
    await tester.pumpAndSettle();
    expect(tester.getRect(search).top, closeTo(before.top, 1));
    expect(tester.getRect(search).left, closeTo(before.left, 1));
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(tester.getRect(search).top, closeTo(before.top, 1));
    expect(tester.takeException(), isNull);
  });
}

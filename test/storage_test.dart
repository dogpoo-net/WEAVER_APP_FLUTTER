import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/project_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  setUp(() {
    elements.clear();
    SharedPreferences.setMockInitialValues({});
  });
  test('JSON restores identity, dates, colors, independent paragraphs and projects', () {
    final e = elements.add('작은 생각');
    restoreWordColors({'작은 생각': 210});
    final p = const Paragraph('작은 생각', ParagraphRole.title);
    final notes = [
      Note('작은 생각')..paragraphs = [p],
      Note('작은 생각')..project = WritingProject([p], ['작은 생각'], name: '내 프로젝트'),
    ];
    final json = WorkspaceSnapshot.encode(notes);
    elements.clear();
    final snapshot = WorkspaceSnapshot.decode(json);
    snapshot.apply();
    expect(elements.records['작은 생각']!.id, e.id);
    expect(elements.records['작은 생각']!.createdAt, e.createdAt);
    expect(exportWordColors()['작은 생각'], 210);
    expect(snapshot.notes.first.paragraphs!.single.role, ParagraphRole.title);
    expect(snapshot.notes.last.project!.name, '내 프로젝트');
    expect(elements.sources.values.single.single.isProject, isTrue);
    final broken = jsonDecode(json) as Map<String, dynamic>;
    broken['version'] = 999;
    expect(
      () => WorkspaceSnapshot.decode(jsonEncode(broken)),
      throwsFormatException,
    );
    expect(elements.words, ['작은 생각']);
  });
  testWidgets('saved notes survive a fresh app instance', (tester) async {
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.enterText(find.byType(TextField).first, '저장된 구절');
    await tester.pump();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(storage.read(), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.pumpAndSettle();
    expect(find.text('저장된 구절'), findsOneWidget);
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(storage.read(), isNotNull);
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모두 삭제'));
    await tester.pumpAndSettle();
    expect(storage.read(), isNull);
    expect(
      storage.preferences.getString('${WorkspaceStorage.key}.previous'),
      isNull,
    );
    expect(elements.words, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.pumpAndSettle();
    expect(find.text('저장된 구절'), findsNothing);
  });
}

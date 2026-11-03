import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/main.dart';
import 'package:weaver/features/inbox/project_folders.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  setUp(() { elements.clear(); paragraphFolders.clear(); elementFolders.clear(); });
  test('paragraph and element folders and search visibility survive reload', () {
    paragraphFolders.add('문단 폴더');
    elementFolders.add('원소 폴더');
    elements.add('숨긴 원소 #비공개')..folder = '원소 폴더'..hiddenFromSearch = true;
    elements.add('태그로 숨긴 원소 #자료');
    elements.add('보이는 원소');
    elements.setTagHidden('자료', true);
    final note = Note('문단 원문')..folder = '문단 폴더'..paragraphs = [const Paragraph('문단 원문', ParagraphRole.body)];
    final snapshot = WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([note]));
    snapshot.apply();
    expect(paragraphFolders, ['문단 폴더']);
    expect(elementFolders, ['원소 폴더']);
    expect(snapshot.notes.single.folder, '문단 폴더');
    expect(elements.records['숨긴 원소']!.folder, '원소 폴더');
    expect(elements.visibleWords, ['보이는 원소']);
    expect(elements.matches('숨긴 원소를 쓴 글').map((hit) => hit.word), ['숨긴 원소']);
    elements.setHidden('숨긴 원소', false);
    elements.setTagHidden('자료', false);
    expect(elements.visibleWords, ['숨긴 원소', '태그로 숨긴 원소', '보이는 원소']);
  });

  testWidgets('hidden elements disappear from main and assist without deleting their text', (tester) async {
    elements.add('숨긴 원소').hiddenFromSearch = true;
    elements.add('보이는 원소');
    SharedPreferences.setMockInitialValues({WorkspaceStorage.key: WorkspaceSnapshot.encode([])});
    final storage = WorkspaceStorage(await SharedPreferences.getInstance());
    await tester.pumpWidget(MyApp(storage: storage));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == '숨긴 원소'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is WordBadge && w.word == '보이는 원소'), findsOneWidget);
    await tester.tap(find.text('문단 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('paragraph-0')), '숨긴');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion-숨긴 원소')), findsNothing);
    expect(elements.records.containsKey('숨긴 원소'), isTrue);
  });

  testWidgets('desktop folder dialog submits on Enter and cancels on Escape', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.ensureVisible(find.byTooltip('문단 폴더 만들기'));
    await tester.tap(find.byTooltip('문단 폴더 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '폴더 이름'), '새 문단 폴더');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(paragraphFolders, ['새 문단 폴더']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('원소 폴더 만들기'), findsNothing);
    await tester.ensureVisible(find.byTooltip('해시태그 폴더 만들기'));
    await tester.tap(find.byTooltip('해시태그 폴더 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '폴더 이름'), '취소할 폴더');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(elementFolders, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS}));
}

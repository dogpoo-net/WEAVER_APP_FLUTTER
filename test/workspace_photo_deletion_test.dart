import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/document_syntax.dart';
import 'package:weaver/features/inbox/document_visual_block.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/workspace_photo.dart';
import 'package:weaver/features/inbox/workspace_photo_actions.dart';

void main() {
  testWidgets('photo deletion lists documents and leaves a missing photo cover', (tester) async {
    const id = 'workspace-photo-test';
    const source = '<photo id="workspace-photo-test">';
    workspacePhotos[id] = WorkspacePhoto(PhotoAttachment(id, '사진'), DateTime.utc(2026), 1);
    final key = Object();
    elements.sources[key] = [ElementSource('여행 기록', source, isProject: true)];
    addTearDown(() {
      elements.sources.remove(key);
      workspacePhotos.remove(id);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => Column(children: [
        TextButton(onPressed: () => deleteWorkspacePhoto(context, null, id, onChanged: () {}),
            child: const Text('사진 삭제')),
        DocumentVisualBlockView(parseDocumentVisualBlock(source)!),
      ]),
    ))));
    await tester.tap(find.text('사진 삭제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((dialog.title as Text).data, '사진 삭제');
    expect(find.descendant(of: find.byWidget(dialog.content!),
        matching: find.text('다음 항목에서 사용 중인 사진입니다. 정말 삭제하시겠어요?')), findsOneWidget);
    expect(find.text('여행 기록'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(workspacePhotos.containsKey(id), isTrue);
    await tester.tap(find.text('사진 삭제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('삭제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(workspacePhotos.containsKey(id), isFalse);
    expect(find.text('사진없음'), findsOneWidget);
  });
}

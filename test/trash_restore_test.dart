import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/inbox_page.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/trash_page.dart';
import 'package:weaver/features/inbox/word_badge.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';

void main(){
 setUp((){SharedPreferences.setMockInitialValues({});elements.clear();memoBoxes.clear();});
 Future<void> openTrash(WidgetTester tester,WorkspaceStorage storage)async{
  await tester.pumpWidget(MaterialApp(home:InboxPage(storage:storage,themeMode:ThemeMode.light,onThemeChanged:(_){})));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('메뉴 열기'));await tester.pumpAndSettle();await tester.ensureVisible(find.text('휴지통'));await tester.tap(find.text('휴지통'));await tester.pumpAndSettle();
  await tester.tap(find.descendant(of:find.byType(TrashPage),matching:find.byType(WordBadge)).first);await tester.pumpAndSettle();
 }
 testWidgets('restore preserves identity and attachments, persists and requests content sync',(tester)async{
  final original=elements.add('복구 대상 #자료')..photos.add(const PhotoAttachment('photo','image.png'))..recordings.add(const VoiceAttachment('audio',3000))..location=ThoughtLocation(35,129,0,DateTime(2026));
  final box=MemoBox('보관함',ids:[original.id]);memoBoxes.add(box);elements.remove(original.text);
  final storage=WorkspaceStorage(await SharedPreferences.getInstance());await storage.write(WorkspaceSnapshot.encode([]));var syncs=0;
  storage.syncContent=()async{syncs++;final saved=WorkspaceSnapshot.decode(storage.read()!);expect(saved.trashRecords,isEmpty);expect(saved.records.single.id,original.id);};
  await openTrash(tester,storage);await tester.tap(find.text('복구'));await tester.pumpAndSettle();
  final restored=elements.records[original.text]!;expect(restored.id,original.id);expect(restored.createdAt,original.createdAt);expect(restored.deletedAt,isNull);expect(restored.tags,{'자료'});expect(restored.photos.single.id,'photo');expect(restored.recordings.single.id,'audio');expect(restored.location!.latitude,35);expect(syncs,greaterThan(0));expect(elements.trash,isEmpty);expect(find.text('생각을 복구했습니다.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('same-text collision does not remove trash or overwrite active record',(tester)async{
  final trashed=elements.add('중복');elements.remove(trashed.text);final active=elements.add('중복');
  final storage=WorkspaceStorage(await SharedPreferences.getInstance());await storage.write(WorkspaceSnapshot.encode([]));
  await openTrash(tester,storage);await tester.tap(find.text('복구'));await tester.pumpAndSettle();
  expect(elements.records['중복']!.id,active.id);expect(elements.trash.containsKey(trashed.id),true);expect(find.textContaining('같은 내용의 생각이 이미 있습니다.'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('offline restore stays on disk and retry uses the same record',(tester)async{
  final original=elements.add('오프라인 복구');elements.remove(original.text);
  final storage=WorkspaceStorage(await SharedPreferences.getInstance());await storage.write(WorkspaceSnapshot.encode([]));var offline=true;
  storage.syncContent=()async{if(offline)throw StateError('offline');};
  await openTrash(tester,storage);await tester.tap(find.text('복구'));await tester.pumpAndSettle();
  expect(WorkspaceSnapshot.decode(storage.read()!).records.single.id,original.id);expect(find.textContaining('복구 내용은 이 기기에 보관했습니다.'),findsOneWidget);
  offline=false;await tester.tap(find.text('복구'));await tester.pumpAndSettle();expect(elements.records,hasLength(1));expect(elements.trash,isEmpty);
  await tester.pumpWidget(const SizedBox());
 });
}

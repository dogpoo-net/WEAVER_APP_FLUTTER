import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weaver/features/capture/capture_models.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/memo_boxes.dart';
import 'package:weaver/features/inbox/trash_page.dart';
import 'package:weaver/features/inbox/workspace_storage.dart';
import 'package:weaver/features/sync/workspace_backup.dart';

class MemoryMedia implements BackupMedia {
  final files = <String, Uint8List>{};
  bool fail = false;
  @override
  Future<Uint8List?> read(String id) async => files[id];
  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (fail) throw StateError('Disk full');
    files[id] = bytes;
  }
  @override
  Future<void> delete(String id) async { files.remove(id); }
}
void main() {
  setUp(() { elements.clear(); memoBoxes.clear(); SharedPreferences.setMockInitialValues({}); });
  test('trash preserves identity, tags, dates, photos and audio across reload', () {
    final a = elements.add('사진 생각 #자료')
      ..photos.add(const PhotoAttachment('photo', '사진.jpg'))
      ..recordings.add(const VoiceAttachment('voice', 1200));
    final b = elements.add('연결 상대');
    elements.connect(a.id, [b.id]);
    elements.remove(a.text);
    expect(elements.words, [b.text]);
    expect(elements.tags, isNot(contains('자료')));
    expect(b.connections, isEmpty);
    WorkspaceSnapshot.decode(WorkspaceSnapshot.encode([])).apply();
    final restored = elements.trash[a.id]!;
    expect(restored.tags, {'자료'});
    expect(restored.createdAt, a.createdAt);
    expect(restored.deletedAt, isNotNull);
    expect(restored.photos.single.id, 'photo');
    expect(restored.recordings.single.id, 'voice');
  });
  test('JSON backup transfers attachment bytes and stages without overwriting local files', () async {
    final media = MemoryMedia()..files['photo'] = Uint8List.fromList([1, 2, 3]);
    elements.add('첨부')..photos.add(const PhotoAttachment('photo', 'original.jpg'));
    final captured = await WorkspaceBackup.capture(WorkspaceSnapshot.encode([]), media);
    final decoded = WorkspaceBackup.decode(captured.encode());
    expect(decoded.media['photo'], [1, 2, 3]);
    media.files['photo'] = Uint8List.fromList([9]);
    final staged = await decoded.stage(media);
    final record = WorkspaceSnapshot.decode(staged.workspace).records.single;
    expect(record.photos.single.id, isNot('photo'));
    expect(media.files[record.photos.single.id], [1, 2, 3]);
    expect(media.files['photo'], [9]);
  });
  test('missing attachments prevent incomplete backups and restore', () async {
    elements.add('첨부')..photos.add(const PhotoAttachment('missing', '사진'));
    final raw = WorkspaceSnapshot.encode([]);
    await expectLater(WorkspaceBackup.capture(raw, MemoryMedia()), throwsA(isA<BackupFailure>()));
    expect(() => WorkspaceBackup.decode(raw), throwsA(isA<BackupFailure>()));
    expect(elements.words, ['첨부']);
  });
  test('API uses confirmed account and JSON string contract; checks application errors', () async {
    final backup = WorkspaceBackup(WorkspaceSnapshot.encode([]), {});
    final requests = <http.Request>[];
    final api = WeaverBackupApi(client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('insertWeaverTestData')) return http.Response('{"code":0,"msg":"ok"}', 200);
      return http.Response(jsonEncode({'code': '0', 'DATA': backup.encode(), 'msg': 'ok'}), 200);
    }));
    await api.upload('owner@example.com', backup);
    await api.download('owner@example.com');
    expect(requests.every((r) => r.method == 'POST'), isTrue);
    final upload = jsonDecode(requests.first.body) as Map;
    expect(upload.keys.toSet(), {'account', 'jsonData'});
    expect(upload['account'], 'owner@example.com');
    expect(upload['jsonData'], isA<String>());
    expect(jsonDecode(requests.last.body), {'account': 'owner@example.com'});
    api.close();
    final failing = WeaverBackupApi(client: MockClient((_) async => http.Response('{"code":9,"msg":"failed"}', 200)));
    await expectLater(failing.download('owner@example.com'), throwsA(isA<BackupFailure>()));
    failing.close();
  });
  test('invalid import leaves current snapshot intact; valid import retains pre-import backup', () async {
    final prefs = await SharedPreferences.getInstance();
    final storage = WorkspaceStorage(prefs);
    elements.add('기존');
    final old = WorkspaceSnapshot.encode([]);
    await storage.write(old);
    expect(() => storage.replaceFromBackup('{"version":99}', closed: true), throwsFormatException);
    expect(storage.read(), old);
    elements.clear(); elements.add('가져온 생각');
    final next = WorkspaceSnapshot.encode([]);
    await storage.replaceFromBackup(next, closed: false);
    expect(storage.read(), next);
    expect(jsonDecode(prefs.getString('${WorkspaceStorage.key}.beforeImport')!)[WorkspaceStorage.key], old);
  });
  testWidgets('trash search and permanent delete confirmation', (tester) async {
    final a = elements.add('버릴 생각 #자료'); elements.remove(a.text);
    await tester.pumpWidget(MaterialApp(home: TrashPage(onDelete: (id) async { elements.trash.remove(id); elements.refreshVisibility(); })));
    await tester.enterText(find.byKey(const ValueKey('trash-search')), '#자료'); await tester.pumpAndSettle();
    await tester.tap(find.text('버릴 생각').first); await tester.pumpAndSettle();
    await tester.tap(find.text('영구 삭제')); await tester.pumpAndSettle();
    await tester.tap(find.text('취소')); await tester.pumpAndSettle();
    expect(elements.trash, isNotEmpty);
    await tester.tap(find.text('영구 삭제')); await tester.pumpAndSettle();
    await tester.tap(find.text('영구 삭제').last); await tester.pumpAndSettle();
    expect(elements.trash, isEmpty);
  });
}

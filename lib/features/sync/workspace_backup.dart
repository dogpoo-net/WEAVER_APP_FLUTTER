import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../capture/media_storage.dart';
import '../inbox/workspace_storage.dart';

class BackupFailure implements Exception {
  const BackupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class BackupMedia {
  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List bytes);
  Future<void> delete(String id);
}
class DeviceBackupMedia implements BackupMedia {
  @override
  Future<Uint8List?> read(String id) => MediaStorage.read(id);
  @override
  Future<void> write(String id, Uint8List bytes) => MediaStorage.write(id, bytes);
  @override
  Future<void> delete(String id) => MediaStorage.delete(id);
}

/// One temporary JSON payload, including binary attachments encoded as Base64.
/// Workspace validation always happens before any existing data is changed.
class WorkspaceBackup {
  WorkspaceBackup(this.workspace, this.media, {this.theme, this.graphs, this.closed = true});
  final String workspace;
  final Map<String, Uint8List> media;
  final String? theme, graphs;
  final bool closed;
  static const maxCharacters = 64 * 1024 * 1024;
  static Set<String> attachmentIds(WorkspaceSnapshot snapshot) => {
    for (final r in [...snapshot.records, ...snapshot.trashRecords]) ...[
      ...r.photos.map((p) => p.id), ...r.recordings.map((r) => r.id),
    ],
  };
  static Future<WorkspaceBackup> capture(String workspace, BackupMedia store,
      {String? theme, String? graphs, bool closed = true}) async {
    final snapshot = WorkspaceSnapshot.decode(workspace);
    final files = <String, Uint8List>{};
    var size = workspace.length;
    for (final id in attachmentIds(snapshot)) {
      final bytes = await store.read(id);
      if (bytes == null || bytes.isEmpty) throw const BackupFailure('첨부파일을 읽지 못했습니다. 불완전한 데이터는 전송하지 않았습니다.');
      size += (bytes.length * 4 / 3).ceil();
      if (size > maxCharacters) throw const BackupFailure('테스트 백업 한도(64MB)를 초과했습니다.');
      files[id] = bytes;
    }
    return WorkspaceBackup(workspace, files, theme: theme, graphs: graphs, closed: closed);
  }
  String encode() {
    final value = jsonEncode({'format': 'weaver.backup', 'version': 1,
      'workspace': jsonDecode(workspace), 'media': media.map((id, bytes) => MapEntry(id, base64Encode(bytes))),
      'theme': theme, 'graphs': graphs, 'showClosedThoughts': closed});
    if (value.length > maxCharacters) throw const BackupFailure('테스트 백업 한도(64MB)를 초과했습니다.');
    return value;
  }
  factory WorkspaceBackup.decode(dynamic input) {
    if (input is String && input.length > maxCharacters) throw const BackupFailure('가져올 데이터가 너무 큽니다.');
    final data = input is String ? jsonDecode(input) : input;
    if (data is! Map) throw const BackupFailure('서버 데이터 형식이 올바르지 않습니다.');
    final bundled = data['format'] == 'weaver.backup';
    if (bundled && data['version'] != 1) throw const BackupFailure('지원하지 않는 백업 버전입니다.');
    final raw = jsonEncode(bundled ? data['workspace'] : data);
    final snapshot = WorkspaceSnapshot.decode(raw);
    final files = <String, Uint8List>{};
    final source = bundled ? data['media'] : null;
    for (final id in attachmentIds(snapshot)) {
      if (source is! Map || source[id] is! String) throw const BackupFailure('백업에 필요한 사진·음성 파일이 없습니다. 현재 데이터는 유지됩니다.');
      final bytes = base64Decode(source[id] as String);
      if (bytes.isEmpty) throw const BackupFailure('백업 첨부파일이 비어 있습니다.');
      files[id] = bytes;
    }
    final theme = bundled ? data['theme'] as String? : null;
    final graphs = bundled ? data['graphs'] as String? : null;
    if (theme != null && jsonDecode(theme) is! Map) throw const FormatException('Invalid theme');
    if (graphs != null && jsonDecode(graphs) is! Map) throw const FormatException('Invalid layouts');
    return WorkspaceBackup(raw, files, theme: theme, graphs: graphs,
      closed: !bundled || data['showClosedThoughts'] != false);
  }

  /// Remap media IDs so staging an import cannot overwrite local/backup files.
  Future<WorkspaceBackup> stage(BackupMedia store) async {
    final data = jsonDecode(workspace) as Map<String, dynamic>;
    final prefix = 'import-${DateTime.now().microsecondsSinceEpoch}';
    final names = <String, String>{};
    var index = 0;
    for (final id in media.keys) { names[id] = '$prefix-${index++}'; }
    for (final r in [...(data['elements'] as List), ...(data['trash'] as List? ?? [])]) {
      for (final file in [...(r['photos'] as List? ?? []), ...(r['recordings'] as List? ?? [])]) {
        file['id'] = names[file['id']]!;
      }
    }
    final written = <String>[];
    try {
      for (final entry in media.entries) {
        final id = names[entry.key]!;
        written.add(id);
        await store.write(id, entry.value);
      }
    } catch (_) {
      for (final id in written) { try { await store.delete(id); } catch (_) {} }
      rethrow;
    }
    return WorkspaceBackup(jsonEncode(data), {for (final e in media.entries) names[e.key]!: e.value},
      theme: theme, graphs: graphs, closed: closed);
  }
}

class WeaverBackupApi {
  WeaverBackupApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const base = 'https://api.dogpoo.net/dogpoo/weaver/api/test/';
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client.post(Uri.parse('$base$path'),
        headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(body)).timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) throw BackupFailure('서버 요청에 실패했습니다. (HTTP ${response.statusCode})');
      if (response.bodyBytes.length > WorkspaceBackup.maxCharacters * 2) throw const BackupFailure('서버 응답이 너무 큽니다.');
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (result is! Map<String, dynamic>) throw const BackupFailure('서버 응답 형식이 올바르지 않습니다.');
      if (result['code'].toString() != '0') throw BackupFailure(result['msg'] is String ? result['msg'] as String : '서버에서 요청을 처리하지 못했습니다.');
      return result;
    } on BackupFailure { rethrow; }
    catch (_) { throw const BackupFailure('서버에 연결하지 못했거나 응답을 읽지 못했습니다. 네트워크와 서버의 CORS 설정을 확인해주세요.'); }
  }
  Future<void> upload(String account, WorkspaceBackup backup) async {
    if (account.isEmpty) throw const BackupFailure('Google 로그인이 필요합니다.');
    await _post('insertWeaverTestData', {'account': account, 'jsonData': backup.encode()});
  }
  Future<WorkspaceBackup> download(String account) async {
    if (account.isEmpty) throw const BackupFailure('Google 로그인이 필요합니다.');
    final response = await _post('getWeaverTestData', {'account': account});
    dynamic data = response['DATA'];
    if (data is Map && data.containsKey('jsonData')) data = data['jsonData'];
    try { return WorkspaceBackup.decode(data); }
    on BackupFailure { rethrow; }
    catch (_) { throw const BackupFailure('저장된 서버 데이터를 검증하지 못했습니다. 현재 데이터는 유지됩니다.'); }
  }
  void close() => _client.close();
}

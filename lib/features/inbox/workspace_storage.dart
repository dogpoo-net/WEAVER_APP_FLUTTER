import 'project_folders.dart';

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'element_store.dart';
import 'paragraph_editor.dart';
import 'project_page.dart';
import 'word_badge.dart';

class Note {
  Note(this.content, {DateTime? created})
    : createdAt = created ?? DateTime.now();
  String content;
  List<Paragraph>? paragraphs;
  WritingProject? project;
  final DateTime createdAt;
  String get title => project?.name ?? content.trim().split('\n').first.trim();
}

class WorkspaceSnapshot {
  WorkspaceSnapshot(
    this.notes,
    this.records,
    this.colors, [
    this.folders = const [],
    this.tagFolders = const [],
    this.tagAssignments = const {},
  ]);
  final List<String> folders;
  final List<String> tagFolders;
  final Map<String, String> tagAssignments;
  final List<Note> notes;
  final List<ElementRecord> records;
  final Map<String, double> colors;
  static Map<String, dynamic> paragraph(Paragraph p) => {
    'text': p.text,
    'role': p.role.name,
  };
  static String encode(List<Note> notes) => jsonEncode({
    'version': 1,
    'folders': projectFolders,
    'hashtagFolders': hashtagFolders,
    'hashtagFolderAssignments': hashtagFolderAssignments,
    'elements': elements.records.values
        .map(
          (r) => {
            'id': r.id,
            'text': r.text,
            'createdAt': r.createdAt.toIso8601String(),
            'tags': r.tags.toList(),
          },
        )
        .toList(),
    'colors': exportWordColors(),
    'notes': notes
        .map(
          (n) => {
            'content': n.content,
            'createdAt': n.createdAt.toIso8601String(),
            'paragraphs': n.paragraphs?.map(paragraph).toList(),
            'project': n.project == null
                ? null
                : {
                    'name': n.project!.name,
                    'folder': n.project!.folder,
                    'words': n.project!.words,
                    'paragraphs': n.project!.paragraphs.map(paragraph).toList(),
                  },
          },
        )
        .toList(),
  });
  static WorkspaceSnapshot decode(String json) {
    if (json.length > 10000000) throw const FormatException('Backup too large');
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Unsupported version');
    }
    List<Paragraph> paragraphs(dynamic raw) => (raw as List)
        .map(
          (p) => Paragraph(
            p['text'] as String,
            ParagraphRole.values.byName(p['role'] as String),
          ),
        )
        .toList();
    final records = (data['elements'] as List).map((r) {
      final text = r['text'] as String;
      if (text.trim().isEmpty) throw const FormatException('Empty element');
      return ElementRecord.restored(
        r['id'] as String,
        text,
        DateTime.parse(r['createdAt'] as String),
        tags: ((r['tags'] ?? []) as List).cast<String>(),
      );
    }).toList();
    if (records.map((r) => r.text).toSet().length != records.length ||
        records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('Duplicate elements');
    }
    final notes = (data['notes'] as List).map((n) {
      final note = Note(
        n['content'] as String,
        created: DateTime.parse(n['createdAt'] as String),
      );
      if (n['paragraphs'] != null) {
        note.paragraphs = paragraphs(n['paragraphs']);
      }
      final p = n['project'];
      if (p != null) {
        note.project = WritingProject(
          paragraphs(p['paragraphs']),
          (p['words'] as List).cast<String>(),
          name: p['name'] as String,
          folder: p['folder'] as String?,
        );
        note.paragraphs = note.project!.paragraphs;
        note.content = note.paragraphs!.map((p) => p.text).join('\n\n');
      }
      return note;
    }).toList();
    final colors = (data['colors'] as Map<String, dynamic>).map((key, value) {
      final hue = (value as num).toDouble();
      if (!hue.isFinite || hue < 0 || hue >= 360) {
        throw const FormatException('Invalid color');
      }
      return MapEntry(key, hue);
    });
    final folders = ((data['folders'] ?? []) as List)
        .cast<String>()
        .toSet()
        .toList();
    for (final n in notes) {
      final f = n.project?.folder;
      if (f != null && !folders.contains(f)) folders.add(f);
    }
    final tagFolders = ((data['hashtagFolders'] ?? []) as List)
        .cast<String>()
        .toSet()
        .toList();
    final assignments = Map<String, String>.from(
      data['hashtagFolderAssignments'] ?? {},
    );
    for (final folder in assignments.values) {
      if (!tagFolders.contains(folder)) tagFolders.add(folder);
    }
    return WorkspaceSnapshot(
      notes,
      records,
      colors,
      folders,
      tagFolders,
      assignments,
    );
  }

  void apply() {
    hashtagFolders
      ..clear()
      ..addAll(tagFolders);
    hashtagFolderAssignments
      ..clear()
      ..addAll(tagAssignments);
    projectFolders
      ..clear()
      ..addAll(folders);
    elements.clear();
    for (final record in records) {
      elements.records[record.text] = record;
    }
    restoreWordColors(colors);
    for (final note in notes) {
      final project = note.project;
      if (project != null) {
        elements.indexProject(project);
      }
    }
  }
}

class WorkspaceStorage {
  WorkspaceStorage(this.preferences);
  final SharedPreferences preferences;
  static const key = 'weaver.workspace.v1';
  Future<void> _pending = Future.value();
  String? read() => preferences.getString(key);
  Future<void> clear() {
    final task = _pending.catchError((Object _) {}).then((_) async {
      if (!await preferences.remove(key)) throw StateError('Clear failed');
      if (!await preferences.remove('$key.previous')) {
        throw StateError('Clear backup failed');
      }
    });
    _pending = task;
    return task;
  }

  Future<void> write(String data) {
    final task = _pending.catchError((Object _) {}).then((_) async {
      final old = preferences.getString(key);
      if (old != null && !await preferences.setString('$key.previous', old)) {
        throw StateError('Backup failed');
      }
      if (!await preferences.setString(key, data)) {
        throw StateError('Save failed');
      }
    });
    _pending = task;
    return task;
  }
}

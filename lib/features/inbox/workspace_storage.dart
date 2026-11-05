import 'element_binding.dart';
import 'memo_boxes.dart';
import 'tag_colors.dart';
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
  String? folder;
  List<ElementBinding> bindings = [];
  final Set<String> tags = {};
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
    this.paragraphFolderList = const [],
    this.elementFolderList = const [],
    this.hiddenTagList = const [],
    this.tagColors = const {},
    this.boxes = const [],
    this.boxFolders = const [],
  ]);
  final List<String> folders;
  final List<MemoBox> boxes;
  final List<String> boxFolders;
  final List<String> paragraphFolderList, elementFolderList, hiddenTagList;
  final List<String> tagFolders;
  final Map<String, String> tagAssignments;
  final Map<String, int> tagColors;
  final List<Note> notes;
  final List<ElementRecord> records;
  final Map<String, double> colors;
  static Map<String, dynamic> paragraph(Paragraph p) => {
    'text': p.text,
    'role': p.role.name,
    'bindings': p.bindings.map((link) => link.toJson()).toList(),
    'tags': p.tags.toList(),
  };
  static String encode(List<Note> notes) => jsonEncode({
    'version': 1,
    'memoBoxFolders': memoBoxFolders,
    'memoBoxes': [for (final box in memoBoxes) {'name': box.name, 'color': box.color, 'folder': box.folder, 'ids': box.elementIds.toList()}],
    'folders': projectFolders,
    'paragraphFolders': paragraphFolders,
    'elementFolders': elementFolders,
    'hiddenSearchTags': hiddenSearchTags.toList(),
    'hashtagFolders': hashtagFolders,
    'hashtagColors': hashtagColors,
    'hashtagFolderAssignments': hashtagFolderAssignments,
    'elements': elements.records.values
        .map(
          (r) => {
            'id': r.id,
            'text': r.text,
            'createdAt': r.createdAt.toIso8601String(),
            'tags': r.tags.toList(),
            'folder': r.folder,
            'hiddenFromSearch': r.hiddenFromSearch,
          },
        )
        .toList(),
    'colors': exportWordColors(),
    'notes': notes
        .map(
          (n) => {
            'content': n.content,
            'bindings': n.bindings.map((link) => link.toJson()).toList(),
            'folder': n.folder,
            'tags': n.tags.toList(),
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
    List<ElementBinding> bindings(dynamic paragraph) {
      final text = paragraph['text'] as String;
      final result = [for (final link in (paragraph['bindings'] ?? []) as List)
        ElementBinding(link['id'] as String, link['start'] as int, link['end'] as int)]
        ..sort((a, b) => a.start.compareTo(b.start));
      var end = 0;
      for (final link in result) {
        if (link.id.isEmpty || link.start < end || link.end <= link.start || link.end > text.length) {
          throw const FormatException('Invalid element binding');
        }
        end = link.end;
      }
      return result;
    }
    List<Paragraph> paragraphs(dynamic raw) => (raw as List)
        .map(
          (p) => Paragraph(
            p['text'] as String,
            ParagraphRole.values.byName(p['role'] as String),
            tags: Set<String>.from(p['tags'] ?? []),
            bindings: bindings(p),
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
      )..folder = r['folder'] as String?
       ..hiddenFromSearch = (r['hiddenFromSearch'] as bool?) ?? false;
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
      note.bindings = bindings({'text': n['content'], 'bindings': n['bindings']});
      note.folder = n['folder'] as String?;
      note.tags.addAll(List<String>.from(n['tags'] ?? []));
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
    // Older snapshots could store several independent paragraphs in one note.
    // Keep every paragraph and its original date when converting to one per note.
    final migrated = <Note>[];
    for (final note in notes) {
      if (note.project == null && note.paragraphs != null && note.paragraphs!.length > 1) {
        for (final p in note.paragraphs!) {
          migrated.add(Note(p.text, created: note.createdAt)
            ..folder = note.folder
            ..paragraphs = [Paragraph(p.text, ParagraphRole.body, tags: p.tags)]
            ..tags.addAll({...note.tags, ...p.tags}));
        }
      } else {
        if (note.project == null && note.paragraphs != null) {
          note.tags.addAll(note.paragraphs!.expand((p) => p.tags));
        }
        migrated.add(note);
      }
    }
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
    final paragraphFolderNames = List<String>.from(data['paragraphFolders'] ?? []);
    final elementFolderNames = List<String>.from(data['elementFolders'] ?? []);
    for (final note in migrated) {
      if (note.folder != null && !paragraphFolderNames.contains(note.folder)) paragraphFolderNames.add(note.folder!);
    }
    for (final record in records) {
      if (record.folder != null && !elementFolderNames.contains(record.folder)) elementFolderNames.add(record.folder!);
    }
    final tagColors = Map<String, int>.from(data['hashtagColors'] ?? {});
    if (tagColors.values.any((color) => color < 0 || color > 0xFFFFFFFF)) {
      throw const FormatException('Invalid hashtag color');
    }
    return WorkspaceSnapshot(
      migrated,
      records,
      colors,
      folders,
      tagFolders,
      assignments,
      paragraphFolderNames,
      elementFolderNames,
      List<String>.from(data['hiddenSearchTags'] ?? []),
      tagColors,
      [for (final box in (data['memoBoxes'] ?? []) as List) MemoBox(box['name'] as String, color: box['color'] as int, folder: box['folder'] as String?, ids: List<String>.from(box['ids']))],
      List<String>.from(data['memoBoxFolders'] ?? []),
    );
  }

  void apply() {
    memoBoxes..clear()..addAll(boxes);
    memoBoxFolders..clear()..addAll(boxFolders);
    for (final box in boxes) {
      if (box.folder != null && !memoBoxFolders.contains(box.folder)) memoBoxFolders.add(box.folder!);
    }
    hashtagColors..clear()..addAll(tagColors);
    hashtagFolders
      ..clear()
      ..addAll(tagFolders);
    hashtagFolderAssignments
      ..clear()
      ..addAll(tagAssignments);
    projectFolders
      ..clear()
      ..addAll(folders);
    paragraphFolders..clear()..addAll(paragraphFolderList);
    elementFolders..clear()..addAll(elementFolderList);
    elements.clear();
    hiddenSearchTags.addAll(hiddenTagList);
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

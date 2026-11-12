import '../capture/capture_models.dart';
import 'graph_layout.dart';
import 'element_binding.dart';
import 'memo_boxes.dart';
import 'tag_colors.dart';
import 'project_folders.dart';

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'element_store.dart';
import 'paragraph_editor.dart';
import 'project_page.dart';
import 'word_badge.dart';

class Note {
  Note(this.content, {DateTime? created, String? id})
    : id = id ?? 'note-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}', createdAt = created ?? DateTime.now();
  final String id;
  String content;
  DateTime? updatedAt;
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
    this.graphLayout,
    this.boxFolderParents = const {},
    this.trashRecords = const [],
  ]);
  final List<ElementRecord> trashRecords;
  final GraphLayout? graphLayout;
  final Map<String, String> boxFolderParents;
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
  static Map<String, dynamic> recordJson(ElementRecord r) => {
            'id': r.id,
            'text': r.text,
            'createdAt': r.createdAt.toIso8601String(),
            'tags': r.tags.toList(),
            'inlineLinks': r.inlineLinks.map((link) => link.toJson()).toList(),
            'folder': r.folder,
            'hiddenFromSearch': r.hiddenFromSearch,
            if (r.labelColor != null) 'labelColor': r.labelColor,
            'indexLabel': r.indexLabel, 'labelOnLeft': r.labelOnLeft, 'indexLabelColor': r.indexLabelColor,
            'location': r.location?.toJson(),
            'recordings': r.recordings.map((clip) => clip.toJson()).toList(),
            'photos': r.photos.map((photo) => photo.toJson()).toList(),
            'deletedAt': r.deletedAt?.toIso8601String(),
          };
  static String encode(List<Note> notes) => jsonEncode({
    'version': 1,
    'graphLayout': pageGraphLayout.toJson(),
    'memoBoxFolders': memoBoxFolders,
    'memoBoxFolderParents': memoBoxFolderParents,
    'memoBoxes': [for (final box in memoBoxes) {'name': box.name, 'isUnclassified': box.isUnclassified, 'color': box.color, 'folder': box.folder, 'ids': box.elementIds.toList(), 'layout': box.layout.toJson()}],
    'folders': projectFolders,
    'paragraphFolders': paragraphFolders,
    'elementFolders': elementFolders,
    'hiddenSearchTags': hiddenSearchTags.toList(),
    'hashtagFolders': hashtagFolders,
    'hashtagColors': hashtagColors,
    'hashtagFolderAssignments': hashtagFolderAssignments,
    'elements': elements.records.values.map(recordJson).toList(),
    'trash': elements.trash.values.map(recordJson).toList(),
    'colors': exportWordColors(),
    'notes': notes
        .map(
          (n) => {
            'id': n.id,
            'content': n.content,
            'bindings': n.bindings.map((link) => link.toJson()).toList(),
            'folder': n.folder,
            'tags': n.tags.toList(),
            'createdAt': n.createdAt.toIso8601String(),
            if(n.updatedAt!=null)'updatedAt':n.updatedAt!.toIso8601String(),
            'paragraphs': n.paragraphs?.map(paragraph).toList(),
            'project': n.project == null
                ? null
                : {
                    'name': n.project!.name,
                    'id': n.project!.id,
                    'documentLinks': n.project!.documentLinks.map((link) => link.toJson()).toList(),
                    'folder': n.project!.folder,
                    'words': n.project!.words,
                    'document': n.project!.document,
                    'tags': n.project!.tags.toList(),
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
    List<ElementRecord> readRecords(List<dynamic> raw) => raw.map((r) {
      final text = r['text'] as String;
      if (text.trim().isEmpty) throw const FormatException('Empty element');
      return ElementRecord.restored(
        r['id'] as String,
        text,
        DateTime.parse(r['createdAt'] as String),
        tags: ((r['tags'] ?? []) as List).cast<String>(),
      )..inlineLinks = bindings({'text': text, 'bindings': r['inlineLinks']})
       ..folder = r['folder'] as String?
       ..hiddenFromSearch = (r['hiddenFromSearch'] as bool?) ?? false
       ..labelColor = r['labelColor'] is int ? r['labelColor'] as int : null
       ..indexLabel = (r['indexLabel'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()
       ..labelOnLeft = r['labelOnLeft'] == true
       ..indexLabelColor = r['indexLabelColor'] is int ? r['indexLabelColor'] as int : 0xFFFFF59D
       ..location = ThoughtLocation.fromJson(r['location'])
       ..recordings.addAll((r['recordings'] as List? ?? []).map(VoiceAttachment.fromJson))
       ..photos.addAll((r['photos'] as List? ?? []).map(PhotoAttachment.fromJson))
       ..deletedAt = r['deletedAt'] == null ? null : DateTime.parse(r['deletedAt'] as String);
    }).toList();
    final records = readRecords(data['elements'] as List);
    final trashRecords = readRecords((data['trash'] ?? []) as List);
    if ([...records, ...trashRecords].map((r) => r.id).toSet().length != records.length + trashRecords.length) {
      throw const FormatException('Duplicate thought IDs');
    }
    if (records.map((r) => r.text).toSet().length != records.length ||
        records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('Duplicate elements');
    }
    var noteIndex=0;
    final notes = (data['notes'] as List).map((n) {
      final note = Note(
        n['content'] as String,
        created: DateTime.parse(n['createdAt'] as String),
        id: n['id'] as String? ?? 'legacy-note-${n['createdAt']}-${noteIndex++}',
      );
      note.updatedAt=DateTime.tryParse(n['updatedAt'] as String? ?? '');
      note.bindings = bindings({'text': n['content'], 'bindings': n['bindings']});
      if (n['paragraphs'] == null && n['project'] == null) note.bindings.removeWhere((b) => !b.id.startsWith('label:') && !b.id.startsWith('url:') && !b.id.startsWith('project:'));
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
          name: p['name'] as String, id: p['id'] as String?,
          folder: p['folder'] as String?,
        );
        note.project!.document = p['document'] as String?;
        note.project!.documentLinks = bindings({'text': p['document'] ?? '', 'bindings': p['documentLinks']});
        note.project!.tags.addAll(List<String>.from(p['tags'] ?? []));
        note.paragraphs = note.project!.paragraphs;
        note.content = note.project!.content;
      }
      return note;
    }).toList();
    // Older snapshots could store several independent paragraphs in one note.
    // Keep every paragraph and its original date when converting to one per note.
    final migrated = <Note>[];
    for (final note in notes) {
      if (note.project == null && note.paragraphs != null && note.paragraphs!.length > 1) {
        for (var index=0;index<note.paragraphs!.length;index++) {
          final p=note.paragraphs![index];
          migrated.add(Note(p.text, created: note.createdAt,id:'${note.id}-p$index')
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
      [for (final box in (data['memoBoxes'] ?? []) as List) MemoBox(box['name'] as String, isUnclassified: box['isUnclassified'] == true, color: box['color'] as int, folder: box['folder'] as String?, ids: List<String>.from(box['ids']), layout: GraphLayout.fromJson(box['layout']))],
      List<String>.from(data['memoBoxFolders'] ?? []),
      GraphLayout.fromJson(data['graphLayout']),
      Map<String, String>.from(data['memoBoxFolderParents'] ?? {}),
      trashRecords,
    );
  }

  void apply() {
    pageGraphLayout = graphLayout ?? GraphLayout();
    memoBoxes..clear()..addAll(boxes);
    normalizeBoxMemberships();
    memoBoxFolders..clear()..addAll(boxFolders);
    memoBoxFolderParents..clear()..addAll(boxFolderParents);
    normalizeMemoFolders();
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
    elements.trash.addEntries(trashRecords.map((r) => MapEntry(r.id, r)));
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
  WorkspaceStorage(this.preferences, {this.owner});
  final String? owner;
  String? currentUserId;
  final editorResources=<String>[];
  Future<Map<String,dynamic>> Function(String,String,bool)? documentLease;
  bool lastSaveReplaced=false;
  VoidCallback? applyServerSnapshot;
  final liveChanges = ValueNotifier<int>(0);
  final leaseChanges = ValueNotifier<int>(0);
  final leaseStates = <String,Map<String,dynamic>>{};
  Future<bool> Function()? checkRemote;
  Future<void> Function()? syncContent;
  Future<void> Function(String)? syncResource;
  Future<void> Function(String)? reloadResource;
  Future<Map<String,dynamic>> Function(String,String)? takeLease;
  void Function()? onChanged;
  Future<void> Function()? syncNow;
  Future<void> Function()? syncDeleted;
  Future<void> Function()? syncFolders;
  Future<void> Function()? refreshNow;
  Future<void> Function()? pullNow;
  Future<void> Function()? openSharing;
  Future<void> Function()? openWorkspaces;
  String? workspaceName;
  Map<String,dynamic>? Function(String,String)? itemMetadata;
  Future<void> Function(String)? openHistory;
  bool Function()? hasUnsavedInput;
  bool suspended = false;
  String scoped(String name) => owner == null ? name : 'weaver.owned.${base64Url.encode(utf8.encode(owner!))}.$name';
  String get workspaceKey => scoped(key);
  String get layoutsKey => scoped(graphKey);
  String get syncKey => scoped('sync.v1');
  Future<void> flush() => _pending;
  Future<void> writable() async {
    if (suspended) throw StateError('Workspace is no longer active');
    await preferences.reload();
    final claim=preferences.getString('weaver.guest.claim.v1');
    if (claim!=null && (jsonDecode(claim) as Map)['scope']==owner) throw StateError('Guest workspace is being transferred');
  }
  final SharedPreferences preferences;
  static const key = 'weaver.workspace.v1';
  static const themeKey = 'weaver.theme.v1';
  static const graphKey = 'weaver.graph-layouts.v1';
  String? readGraphLayouts() => preferences.getString(layoutsKey);
  Future<void> writeGraphLayouts(String data) {
    final task = _pending.catchError((Object _) {}).then((_) async {
      await writable();
      if (preferences.getString(layoutsKey) == data) return;
      if (!await preferences.setString(layoutsKey, data)) throw StateError('Graph save failed');
    });
    _pending = task;
    return task;
  }
  String? readTheme() => preferences.getString(themeKey);
  Future<void> writeTheme(String data) {
    final task = _pending.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(themeKey, data)) throw StateError('Theme save failed');
    });
    _pending = task;
    return task;
  }
  Future<void> _pending = Future.value();
  String? read() => preferences.getString(workspaceKey);
  Future<void> replaceFromBackup(String workspace, {String? graphs, String? theme, bool? closed}) {
    WorkspaceSnapshot.decode(workspace);
    final task = _pending.catchError((Object _) {}).then((_) async {
      const closedKey = 'weaver.showClosedThoughts.v1';
      final before = <String, Object?>{for (final k in [workspaceKey, layoutsKey, themeKey, closedKey]) k: preferences.get(k)};
      if (!await preferences.setString('$workspaceKey.beforeImport', jsonEncode(before))) throw StateError('Backup failed');
      Future<void> put(String k, Object? value) async {
        final ok = value == null ? await preferences.remove(k) : value is bool
          ? await preferences.setBool(k, value) : await preferences.setString(k, value as String);
        if (!ok) throw StateError('Import save failed');
      }
      try {
        await put(layoutsKey, graphs);
        if (theme != null) await put(themeKey, theme);
        if(closed!=null)await put(closedKey, closed);
        await put(workspaceKey, workspace);
      } catch (_) {
        for (final entry in before.entries) { await put(entry.key, entry.value); }
        rethrow;
      }
    });
    _pending = task;
    return task;
  }

  Future<void> clear() {
    final task = _pending.catchError((Object _) {}).then((_) async {
      if (!await preferences.remove(workspaceKey)) throw StateError('Clear failed');
      if (!await preferences.remove(layoutsKey)) throw StateError('Graph clear failed');
      await preferences.remove('$workspaceKey.beforeImport');
      if (!await preferences.remove('$workspaceKey.previous')) {
        throw StateError('Clear backup failed');
      }
    });
    _pending = task;
    return task;
  }

  Future<void> write(String data) {
    final task = _pending.catchError((Object _) {}).then((_) async {
      await writable();
      final old = preferences.getString(workspaceKey);
      if (old != null && !await preferences.setString('$workspaceKey.previous', old)) {
        throw StateError('Backup failed');
      }
      if (!await preferences.setString(workspaceKey, data)) {
        throw StateError('Save failed');
      }
      onChanged?.call();
    });
    _pending = task;
    return task;
  }
}

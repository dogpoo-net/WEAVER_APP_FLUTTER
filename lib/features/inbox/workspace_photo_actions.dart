import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/capture_models.dart';
import '../capture/media_storage.dart';
import '../capture/photo_gallery.dart';
import 'element_store.dart';
import 'document_syntax.dart';
import 'memo_boxes.dart';
import 'overview_collections.dart' show StoredThumbnail;
import 'workspace_photo.dart';
import 'workspace_routes.dart';
import 'workspace_storage.dart';

enum _PhotoSource { existing, upload }

void _photoMessage(BuildContext context, String message) {
  if (context.mounted)
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openWorkspacePhoto(
  BuildContext context,
  String id,
  WorkspaceStorage? storage,
) async {
  try {
    final bytes = await MediaStorage.read(id, owner: storage?.owner);
    if (!context.mounted) return;
    if (bytes == null) {
      _photoMessage(context, '사진을 불러올 수 없습니다.');
    } else {
      final photo = workspacePhotos[id];
      await showPhoto(
        context,
        bytes,
        metadata: photo == null
            ? null
            : (title: photo.title, label: photo.label),
        editMetadata: photo == null || !(storage?.canvasWritable ?? true)
            ? null
            : () => _editPhotoMetadata(context, id, storage),
      );
    }
  } catch (_) {
    _photoMessage(context, '사진을 불러올 수 없습니다.');
  }
}

Future<PhotoMetadata?> _editPhotoMetadata(
  BuildContext context,
  String id,
  WorkspaceStorage? storage,
) async {
  final photo = workspacePhotos[id];
  if (photo == null) return null;
  var title = photo.title, label = photo.label;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('제목과 라벨'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: title,
            maxLength: 100,
            autofocus: true,
            decoration: const InputDecoration(labelText: '제목'),
            onChanged: (value) => title = value,
          ),
          TextFormField(
            initialValue: label,
            maxLength: 60,
            decoration: const InputDecoration(labelText: '라벨'),
            onChanged: (value) => label = value,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('저장'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return null;
  try {
    await storage?.writable();
    if (!context.mounted) return null;
    final latest = workspacePhotos[id];
    if (latest == null) return null;
    final metadata = (title: title.trim(), label: label.trim());
    workspacePhotos[id] = WorkspacePhoto(
      latest.attachment,
      latest.createdAt,
      latest.aspectRatio,
      title: metadata.title,
      label: metadata.label,
    );
    elements.refreshVisibility();
    await saveWorkspaceContent?.call();
    return metadata;
  } catch (error) {
    _photoMessage(context, '사진 정보를 저장하지 못했습니다. $error');
    return null;
  }
}

Future<void> createWorkspacePhoto(
  BuildContext context,
  WorkspaceStorage? storage, {
  MemoBox? box,
  bool uploadOnly = false,
  required VoidCallback onChanged,
}) async {
  final photo = await chooseWorkspacePhoto(
    context,
    storage,
    copyExisting: true,
    uploadOnly: uploadOnly,
  );
  if (photo == null || !context.mounted) return;
  try {
    if (box != null && memoBoxes.contains(box)) moveThoughtToBox(photo.id, box);
    onChanged();
    await saveWorkspaceContent?.call();
  } catch (error) {
    _photoMessage(context, '사진을 저장하지 못했습니다. $error');
  }
}

Future<PhotoAttachment?> chooseWorkspacePhoto(
  BuildContext context,
  WorkspaceStorage? storage, {
  bool copyExisting = false,
  bool uploadOnly = false,
}) async {
  final source = uploadOnly ? _PhotoSource.upload : await showDialog<_PhotoSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('사진'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _PhotoSource.existing),
          child: const Text('가져오기'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _PhotoSource.upload),
          child: const Text('사진 업로드'),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return null;
  try {
    Uint8List? bytes;
    String name;
    if (source == _PhotoSource.existing) {
      final attachments = {
        for (final thought in elements.records.values)
          for (final photo in thought.photos) photo.id: photo,
        for (final photo in workspacePhotos.values) photo.id: photo.attachment,
      }.values.toList();
      var columns = 3;
      final attachment = await showDialog<PhotoAttachment>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('사진 가져오기'),
            content: SizedBox(
              width: 480,
              height: 360,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${attachments.length}장')),
                      const Text('열'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: columns,
                        items: [
                          for (var count = 2; count <= 6; count++)
                            DropdownMenuItem(
                              value: count,
                              child: Text('$count'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) update(() => columns = value);
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: attachments.isEmpty
                        ? const Center(child: Text('가져올 사진이 없습니다.'))
                        : GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                            itemCount: attachments.length,
                            itemBuilder: (context, index) {
                              final photo = attachments[index];
                              return InkWell(
                                onTap: () => Navigator.pop(context, photo),
                                child: StoredThumbnail(
                                  id: photo.id,
                                  name: photo.name,
                                  owner: storage?.owner,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      );
      if (attachment == null || !context.mounted) return null;
      if (!copyExisting && workspacePhotos.containsKey(attachment.id))
        return attachment;
      name = attachment.name;
      bytes = await MediaStorage.read(attachment.id, owner: storage?.owner);
    } else {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (photo == null || !context.mounted) return null;
      if (await photo.length() > 10 * 1024 * 1024) {
        _photoMessage(context, '사진 한 장은 10MB 이하로 선택해주세요.');
        return null;
      }
      name = photo.name;
      bytes = await photo.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) throw StateError('사진을 읽을 수 없습니다.');
    if (!context.mounted) return null;
    await storage?.writable();
    final codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    final ratio = frame.image.width / frame.image.height;
    frame.image.dispose();
    if (!context.mounted) return null;
    final created = DateTime.now().toUtc();
    final id = 'workspace-photo-${created.microsecondsSinceEpoch}';
    await MediaStorage.write(id, bytes, owner: storage?.owner);
    if (!context.mounted) {
      await MediaStorage.delete(id, owner: storage?.owner);
      return null;
    }
    workspacePhotos[id] = WorkspacePhoto(
      PhotoAttachment(id, name),
      created,
      ratio,
    );
    elements.refreshVisibility();
    if (!copyExisting) await saveWorkspaceContent?.call();
    return workspacePhotos[id]?.attachment;
  } catch (error) {
    _photoMessage(context, '사진을 저장하지 못했습니다. $error');
    return null;
  }
}

Future<void> deleteWorkspacePhoto(
  BuildContext context,
  WorkspaceStorage? storage,
  String id, {
  String? thoughtId,
  required VoidCallback onChanged,
}) async {
  final usedIn = [
    for (final entries in elements.sources.values)
      for (final entry in entries)
        if (entry.isProject && DocumentComments(entry.text).visibleText
            .split('\n').any((line) => parseDocumentVisualBlock(line)?.photoId == id))
          entry.label,
  ];
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('사진 삭제'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              usedIn.isEmpty
                  ? '이 사진을 삭제하시겠어요?'
                  : '다음 항목에서 사용 중인 사진입니다. 정말 삭제하시겠어요?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (usedIn.isNotEmpty) ...[
              const Divider(),
              Flexible(child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: usedIn.length,
                  itemBuilder: (_, index) => ListTile(dense: true, title: Text(usedIn[index])),
                ),
              )),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await storage?.writable();
    if (!context.mounted) return;
    if (thoughtId == null) {
      if (workspacePhotos.remove(id) == null) return;
      for (final box in memoBoxes.where((box) => !box.isUnclassified)) {
        box.elementIds.remove(id);
      }
    } else {
      final thought = elements.byId(thoughtId);
      if (thought == null || !thought.photos.any((photo) => photo.id == id))
        return;
      thought.photos.removeWhere((photo) => photo.id == id);
    }
    onChanged();
    elements.refreshVisibility();
    await saveWorkspaceContent?.call();
    final referenced =
        workspacePhotos.containsKey(id) ||
        [
          ...elements.records.values,
          ...elements.trash.values,
        ].any((thought) => thought.photos.any((photo) => photo.id == id));
    if (!referenced) {
      await MediaStorage.delete(id, owner: storage?.owner);
      if (storage != null) {
        await storage.preferences.remove(storage.scoped('media-sent.$id'));
      }
    }
  } catch (error) {
    _photoMessage(context, '사진 삭제를 완료하지 못했습니다. $error');
  }
}

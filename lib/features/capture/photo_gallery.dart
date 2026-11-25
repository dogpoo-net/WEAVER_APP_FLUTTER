import '../capture/photo_image.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'capture_models.dart';
import 'media_storage.dart';

typedef PhotoMetadata = ({String title, String label});

Future<void> showPhoto(
  BuildContext context,
  Uint8List bytes, {
  PhotoMetadata? metadata,
  Future<PhotoMetadata?> Function()? editMetadata,
}) {
  var details = metadata;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('사진'),
            leading: IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (editMetadata != null)
                IconButton(
                  tooltip: '제목과 라벨 수정',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final updated = await editMetadata();
                    if (context.mounted && updated != null)
                      setState(() => details = updated);
                  },
                ),
            ],
          ),
          body: Column(
            children: [
              if (details case final value?)
                if (value.title.isNotEmpty || value.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (value.title.isNotEmpty) Text(value.title),
                        if (value.label.isNotEmpty)
                          Chip(label: Text(value.label)),
                      ],
                    ),
                  ),
              Expanded(
                child: SizedBox.expand(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: SizedBox.expand(
                      child: photoImage(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) =>
                            const Center(child: Text('사진을 표시할 수 없습니다.')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PhotoGallery extends StatelessWidget {
  const PhotoGallery({
    super.key,
    required this.photos,
    this.onDelete,
    this.trailing = const [],
  });
  final List<PhotoAttachment> photos;
  final List<Widget> trailing;
  final ValueChanged<PhotoAttachment>? onDelete;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final photo in photos)
        SizedBox.square(
          dimension: 88,
          child: Stack(
            children: [
              _StoredPhoto(key: ValueKey(photo.id), photo: photo),
              if (onDelete != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: PhotoRemoveButton(onPressed: () => onDelete!(photo)),
                ),
            ],
          ),
        ),
      ...trailing,
    ],
  );
}

class _StoredPhoto extends StatefulWidget {
  const _StoredPhoto({super.key, required this.photo});
  final PhotoAttachment photo;
  @override
  State<_StoredPhoto> createState() => _StoredPhotoState();
}

class _StoredPhotoState extends State<_StoredPhoto> {
  late final _bytes = MediaStorage.read(widget.photo.id);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      return SizedBox.square(
        dimension: 88,
        child: bytes == null
            ? Center(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const CircularProgressIndicator()
                    : const Tooltip(
                        message: '사진을 불러올 수 없습니다',
                        child: Icon(Icons.broken_image_outlined),
                      ),
              )
            : InkWell(
                onTap: () => showPhoto(context, bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoImage(
                    bytes,
                    cacheWidth: 264,
                    fit: BoxFit.cover,
                    semanticLabel: widget.photo.name,
                    errorBuilder: (_, error, stack) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
      );
    },
  );
}

class PhotoRemoveButton extends StatelessWidget {
  const PhotoRemoveButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: '사진 삭제',
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: .25),
      foregroundColor: Colors.white,
      minimumSize: const Size.square(24),
      fixedSize: const Size.square(24),
      padding: const EdgeInsets.all(2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: const Icon(Icons.close, size: 16),
  );
}

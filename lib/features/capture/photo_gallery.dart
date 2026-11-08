import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'capture_models.dart';
import 'media_storage.dart';

void showPhoto(BuildContext context, Uint8List bytes) {
  showDialog<void>(context: context, builder: (context) => Dialog.fullscreen(child: Scaffold(
    appBar: AppBar(title: const Text('첨부 사진'), leading: IconButton(tooltip: '닫기', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
    body: Center(child: InteractiveViewer(minScale: .5, maxScale: 5,
      child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, error, stack) => const Text('사진을 표시할 수 없습니다.')))),
  )));
}
class PhotoGallery extends StatelessWidget {
  const PhotoGallery({super.key, required this.photos});
  final List<PhotoAttachment> photos;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
    for (final photo in photos) _StoredPhoto(key: ValueKey(photo.id), photo: photo),
  ]);
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
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(future: _bytes, builder: (context, snapshot) {
    final bytes = snapshot.data;
    return SizedBox.square(dimension: 88, child: bytes == null
      ? Center(child: snapshot.connectionState == ConnectionState.waiting ? const CircularProgressIndicator() : const Tooltip(message: '사진을 불러올 수 없습니다', child: Icon(Icons.broken_image_outlined)))
      : InkWell(onTap: () => showPhoto(context, bytes), child: ClipRRect(borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, cacheWidth: 264, fit: BoxFit.cover, semanticLabel: widget.photo.name,
          errorBuilder: (_, error, stack) => const Icon(Icons.broken_image_outlined)))));
  });
}

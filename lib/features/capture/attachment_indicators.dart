import 'package:flutter/material.dart';
import '../inbox/element_store.dart';

class AttachmentIndicators extends StatelessWidget {
  const AttachmentIndicators({super.key, required this.record});
  final ElementRecord record;
  static bool hasAttachments(ElementRecord record) =>
    record.recordings.isNotEmpty || record.photos.isNotEmpty || record.location != null;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (record.recordings.isNotEmpty) const Tooltip(message: '음성 메모', child: Icon(Icons.volume_up_outlined, size: 13)),
    if (record.photos.isNotEmpty) const Tooltip(message: '사진', child: Icon(Icons.image_outlined, size: 13)),
    if (record.location != null) const Tooltip(message: '위치 기록', child: Icon(Icons.location_on_outlined, size: 13)),
  ]);
}

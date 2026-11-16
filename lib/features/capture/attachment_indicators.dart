import 'package:flutter/material.dart';
import '../inbox/element_store.dart';

class AttachmentIndicators extends StatelessWidget {
  const AttachmentIndicators({super.key, required this.record,this.vertical=true,this.commentCount=0});
  final ElementRecord record;
  final bool vertical;
  final int commentCount;
  static bool hasAttachments(ElementRecord record) =>
    record.recordings.isNotEmpty || record.photos.isNotEmpty || record.location != null;
  @override
  Widget build(BuildContext context) => Flex(direction:vertical?Axis.vertical:Axis.horizontal,mainAxisSize: MainAxisSize.min, children: [
    if(commentCount>0)Tooltip(message:'댓글',child:Icon(Icons.chat_bubble_outline,size:13,key:ValueKey('comment-icon-${record.id}'))),
    if (record.location != null) const Tooltip(message: '위치 기록', child: Icon(Icons.location_on_outlined, size: 13)),
    if (record.recordings.isNotEmpty) const Tooltip(message: '음성 메모', child: Icon(Icons.mic_none, size: 13)),
    if (record.photos.isNotEmpty) const Tooltip(message: '사진', child: Icon(Icons.image_outlined, size: 13)),
  ]);
}

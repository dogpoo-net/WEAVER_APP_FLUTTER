import 'package:flutter/material.dart';

import 'document_photo.dart';
import 'document_syntax.dart';

class DocumentVisualBlockView extends StatelessWidget {
  const DocumentVisualBlockView(this.block, {super.key});

  final DocumentVisualBlock block;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (block.alignment) {
      DocumentBlockAlignment.left => Alignment.centerLeft,
      DocumentBlockAlignment.center => Alignment.center,
      DocumentBlockAlignment.right => Alignment.centerRight,
    };
    final id = block.photoId;
    return FractionallySizedBox(
      widthFactor: block.widthPercent / 100,
      alignment: alignment,
      child: id == null ? const Divider() : DocumentPhoto(id),
    );
  }
}

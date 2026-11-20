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
    if (id != null) {
      return Align(alignment: alignment, child: DocumentPhoto(id));
    }
    return FractionallySizedBox(
      widthFactor: .6,
      alignment: alignment,
      child: const Divider(),
    );
  }
}

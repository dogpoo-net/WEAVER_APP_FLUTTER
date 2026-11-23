import 'package:flutter/material.dart';

import 'document_photo.dart';
import 'element_store.dart';
import 'workspace_photo.dart';
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
      child: id == null ? const Divider() : ListenableBuilder(
        listenable: elements,
        builder: (context, _) {
          if (workspacePhotos.containsKey(id)) return DocumentPhoto(id);
          return Align(
            alignment: alignment,
            child: Container(
              width: 76, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('사진없음', style: Theme.of(context).textTheme.labelSmall),
            ),
          );
        },
      ),
    );
  }
}

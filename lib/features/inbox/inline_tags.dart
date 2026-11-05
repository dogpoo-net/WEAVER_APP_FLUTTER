import 'package:flutter/material.dart';

class InlineTags extends StatelessWidget {
  const InlineTags({super.key, required this.tags, required this.onRemove});
  final Iterable<String> tags;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 4, children: [
    for (final tag in tags) Tooltip(message: '#$tag 태그 삭제', child: TextButton(
      onPressed: () => onRemove(tag),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: Colors.transparent, side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        minimumSize: const Size(0, 22), tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text('#$tag'),
        const SizedBox(width: 3), const Icon(Icons.close, size: 10)]),
    )),
  ]);
}

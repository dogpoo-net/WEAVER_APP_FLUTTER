import 'package:flutter/material.dart';
import 'element_store.dart';

/// The paper is translucent; the single-line title remains opaque.
class ThoughtLabel extends StatelessWidget {
  const ThoughtLabel({super.key, required this.record, required this.onTap, this.active = false});
  final ElementRecord record;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Tooltip(message: record.indexLabel,
    child: Material(color: Colors.transparent, child: InkWell(onTap: onTap,
      borderRadius: BorderRadius.circular(3), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Color(record.indexLabelColor).withValues(alpha: .6),
          borderRadius: BorderRadius.circular(3),
          border: active ? Border.all(color: Theme.of(context).colorScheme.primary) : null),
        child: Text(record.indexLabel, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF202020), fontSize: 12, fontWeight: FontWeight.w600)),
      ))));
}

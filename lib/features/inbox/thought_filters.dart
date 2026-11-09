import 'package:flutter/material.dart';
import 'memo_boxes.dart';
import 'tag_colors.dart';

class ThoughtFilters extends StatelessWidget {
  const ThoughtFilters({super.key, required this.tags, required this.onFilter, required this.onChanged,
    this.scope, this.box, this.tag});
  final List<String> tags;
  final MemoBox? scope, box;
  final String? tag;
  final void Function(MemoBox? box, String? tag) onFilter;
  final VoidCallback onChanged;
  Widget _chip(String label, Key key, bool selected, VoidCallback onTap, {Widget? avatar}) => Stack(alignment: Alignment.centerLeft, children: [ChoiceChip(
    key: key, avatarBoxConstraints: const BoxConstraints.tightFor(width: 20, height: 20), avatar: avatar == null ? null : const SizedBox.square(dimension: 20), label: Text(label, style: const TextStyle(fontSize: 12)), selected: selected,
    labelPadding: const EdgeInsets.only(left: 2, right: 8),
    showCheckmark: false, visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero,
    onSelected: (_) => onTap()),
    if (avatar != null) Positioned(left: 2, child: avatar),
  ]);
  Widget _color(String tooltip, Color color, VoidCallback onTap) => Tooltip(message: tooltip,
    child: SizedBox.square(dimension: 20, child: InkWell(onTap: onTap, customBorder: const CircleBorder(),
      child: Icon(Icons.circle, size: 14, color: color))));
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Row(children: [
      ChoiceChip(key: const ValueKey('thought-filter-all'), selected: box == null && tag == null,
        showCheckmark: false, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero, labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        label: SizedBox(height: tags.isNotEmpty ? 66 : 30, child: const Center(child: Text('전체', style: TextStyle(fontSize: 12)))),
        onSelected: (_) => onFilter(null, null)),
      const SizedBox(width: 8),
      Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 38, child: Row(children: [
        const Icon(Icons.inventory_2_outlined, size: 18), const SizedBox(width: 8),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final item in scope == null ? memoBoxes : [scope!, ...memoBoxes.where(scope!.isAncestorOf)]) Padding(padding: const EdgeInsets.only(right: 6), child: MemoBoxTarget(
            box: item, onChanged: onChanged, child: _chip(item.path, ValueKey('thought-filter-box-${item.name}'), identical(box, item), () => onFilter(item, null), avatar: _color('${item.name} 상자 색상 변경', Color(item.color), () async {
                final color = await pickHashtagColor(context, item.name, Color(item.color), prefix: '');
                if (color != null && context.mounted) { item.color = color.toARGB32(); onChanged(); }
              })))),
        ])),
      ])),
      if (tags.isNotEmpty) SizedBox(height: 36, child: Row(children: [
        const Icon(Icons.tag, size: 18), const SizedBox(width: 8),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [for (final item in tags)
          Padding(padding: const EdgeInsets.only(right: 6), child: _chip('#$item', ValueKey('thought-filter-tag-$item'), tag == item, () => onFilter(null, item), avatar: _color('#$item 색상 변경', Color(hashtagColors[item] ?? 0xFF90A4AE), () async {
              final color = await pickHashtagColor(context, item, Color(hashtagColors[item] ?? 0xFF90A4AE));
              if (color != null && context.mounted) { hashtagColors[item] = color.toARGB32(); onChanged(); }
            }))),
        ])),
      ])),
      ])),
    ])));
}

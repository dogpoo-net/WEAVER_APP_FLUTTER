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
  Widget _chip(String label, Key key, bool selected, VoidCallback onTap) => ChoiceChip(
    key: key, label: Text(label, style: const TextStyle(fontSize: 12)), selected: selected,
    showCheckmark: false, visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero,
    onSelected: (_) => onTap());
  Widget _color(String tooltip, Color color, VoidCallback onTap) => Tooltip(message: tooltip,
    child: SizedBox.square(dimension: 24, child: InkWell(onTap: onTap, customBorder: const CircleBorder(),
      child: Icon(Icons.circle, size: 14, color: color))));
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 38, child: Row(children: [
        const Icon(Icons.inventory_2_outlined, size: 18), const SizedBox(width: 8),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [
          _chip('전체', const ValueKey('thought-filter-all'), box == null && tag == null, () => onFilter(null, null)),
          for (final item in scope == null ? memoBoxes : [scope!]) Padding(padding: const EdgeInsets.only(left: 6), child: MemoBoxTarget(
            box: item, onChanged: onChanged, child: Row(children: [
              _color('${item.name} 상자 색상 변경', Color(item.color), () async {
                final color = await pickHashtagColor(context, item.name, Color(item.color), prefix: '');
                if (color != null && context.mounted) { item.color = color.toARGB32(); onChanged(); }
              }),
              _chip(item.name, ValueKey('thought-filter-box-${item.name}'), identical(box, item), () => onFilter(item, null)),
            ]))),
        ])),
        TextButton.icon(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
          icon: const Icon(Icons.add, size: 16), label: const Text('상자 만들기', style: TextStyle(fontSize: 12)),
          onPressed: () async { final created = await createMemoBox(context); if (created != null && context.mounted) onChanged(); }),
      ])),
      if (tags.isNotEmpty) SizedBox(height: 36, child: Row(children: [
        const Icon(Icons.tag, size: 18), const SizedBox(width: 8),
        Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [for (final item in tags)
          Padding(padding: const EdgeInsets.only(right: 6), child: Row(children: [
            _color('#$item 색상 변경', Color(hashtagColors[item] ?? 0xFF90A4AE), () async {
              final color = await pickHashtagColor(context, item, Color(hashtagColors[item] ?? 0xFF90A4AE));
              if (color != null && context.mounted) { hashtagColors[item] = color.toARGB32(); onChanged(); }
            }),
            _chip('#$item', ValueKey('thought-filter-tag-$item'), tag == item, () => onFilter(null, item)),
          ])),
        ])),
      ])),
    ])));
}

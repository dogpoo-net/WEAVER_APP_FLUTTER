import 'package:flutter/material.dart';

final hashtagColors = <String, int>{};

const hashtagPalette = <Color>[
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD), Color(0xFF7986CB),
  Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1), Color(0xFF4DB6AC), Color(0xFF81C784),
  Color(0xFFAED581), Color(0xFFDCE775), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE), Color(0xFFBDBDBD), Color(0xFF78909C), Color(0xFF616161),
];

Future<Color?> pickHashtagColor(BuildContext context, String tag, Color? selected, {String prefix = '#'}) => showDialog<Color>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('$prefix$tag 색상', maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(width: 240, height: 192, child: GridView.count(
      key: const ValueKey('hashtag-palette'),
      crossAxisCount: 5,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (var i = 0; i < hashtagPalette.length; i++)
        IconButton(
          key: ValueKey('hashtag-color-$i'),
          tooltip: '색상 ${i + 1}',
          onPressed: () => Navigator.pop(context, hashtagPalette[i]),
          icon: Container(width: 28, height: 28, decoration: BoxDecoration(
            color: hashtagPalette[i], shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
            child: selected == hashtagPalette[i] ? Icon(Icons.check, size: 18,
              color: hashtagPalette[i].computeLuminance() > .4 ? Colors.black : Colors.white) : null),
        ),
      ],
    )),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소'))],
  ),
);

Future<String?> createHashtag(BuildContext context) async {
  final controller = TextEditingController();
  final tag = await showDialog<String>(context: context, builder: (context) {
    void submit() {
      final value = controller.text.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
      if (value.isNotEmpty && !RegExp(r'[\s#.,!?;:،؛؟()\[\]{}]').hasMatch(value)) Navigator.pop(context, value);
    }
    return AlertDialog(title: const Text('해시태그 만들기'), content: TextField(controller: controller, autofocus: true,
      decoration: const InputDecoration(labelText: '태그 이름', prefixText: '#'), onSubmitted: (_) => submit()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), TextButton(onPressed: submit, child: const Text('만들기'))]);
  });
  // The closing route can still paint its TextField during the exit animation.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  if (tag != null) hashtagColors.putIfAbsent(tag, () => 0xFF90A4AE);
  return tag;
}

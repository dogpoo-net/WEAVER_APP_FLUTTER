part of 'element_store.dart';

class ThoughtPageData {
  const ThoughtPageData(
    this.text, [
    this.label = '',
    this.left = false,
    this.color = 0xfffff59d,
    this.links = const [],
  ]);
  factory ThoughtPageData.first(ElementRecord r) => ThoughtPageData(
    r.text,
    r.indexLabel,
    r.labelOnLeft,
    r.indexLabelColor,
    List.of(r.inlineLinks),
  );
  final String text, label;
  final bool left;
  final int color;
  final List<ElementBinding> links;
  Map<String, dynamic> toJson() => {
    'text': text,
    'label': label,
    'left': left,
    'color': color,
    'links': [for (final link in links) link.toJson()],
  };
}

class _ThoughtReading extends StatefulWidget {
  const _ThoughtReading(this.record);
  final ElementRecord record;
  @override
  State<_ThoughtReading> createState() => _ThoughtReadingState();
}

class _ThoughtReadingState extends State<_ThoughtReading> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final pages = [ThoughtPageData.first(r), ...r.extraPages];
    final page = pages[index];
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final colors = Theme.of(context).colorScheme;
    final paper = wordBackgroundColor(context, r.text);
    return Dialog(
      key: const ValueKey('생각읽기'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = (pages.length - index - 1).clamp(0, 5); i > 0; i--)
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(i * 3, i * 3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: paper,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            Material(
              color: paper,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AttachmentIndicators(record: r, commentCount: memoCommentCounts.value[r.id] ?? 0),
                        const Spacer(),
                        IconButton(
                          tooltip: '닫기',
                          iconSize: 17,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: DocumentMarkup(
                          text: page.text,
                          links: page.links,
                          formatting: false,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text('${index + 1} / ${pages.length}'),
                        const Spacer(),
                        if (pages.length > 1) ...[
                          IconButton(
                            tooltip: '이전 페이지',
                            icon: const Icon(Icons.chevron_left),
                            onPressed: index == 0
                                ? null
                                : () => setState(() => index--),
                          ),
                          IconButton(
                            tooltip: '다음 페이지',
                            icon: const Icon(Icons.chevron_right),
                            onPressed: index + 1 == pages.length
                                ? null
                                : () => setState(() => index++),
                          ),
                        ],
                        IconButton(
                          tooltip: '수정',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => Navigator.pop(context, index),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (page.label.isNotEmpty)
              Positioned(
                top: mobile ? -12 : 16,
                left: mobile
                    ? 0
                    : page.left
                    ? -80
                    : null,
                right: mobile
                    ? 0
                    : page.left
                    ? null
                    : -80,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: mobile ? 220 : 100),
                    color: Color(page.color),
                    padding: const EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 12,
                    ),
                    child: Text(
                      page.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(page.color).computeLuminance() > .4
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

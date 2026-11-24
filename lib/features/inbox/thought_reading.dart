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

class ThoughtPaperStack extends StatelessWidget {
  const ThoughtPaperStack({
    super.key,
    required this.remaining,
    required this.paper,
    required this.child,
    this.step = 2,
    this.radius = 6,
  });
  final int remaining;
  final Color paper;
  final Widget child;
  final double step, radius;

  @override
  Widget build(BuildContext context) {
    if (remaining <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = remaining.clamp(0, 5); i > 0; i--)
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(i * step, i * step),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class _ThoughtReading extends StatefulWidget {
  const _ThoughtReading(this.pages, this.initialPage);
  final List<({ElementRecord record, ThoughtPageData page})> pages;
  final int initialPage;
  @override
  State<_ThoughtReading> createState() => _ThoughtReadingState();
}

class _ThoughtReadingState extends State<_ThoughtReading> {
  late int index = widget.initialPage;
  final _moreBelow = <int, bool>{};

  void _updateOverflow(int page, ScrollMetrics metrics) {
    final more = metrics.extentAfter > 1;
    if (mounted && more != (_moreBelow[page] ?? false))
      setState(() => _moreBelow[page] = more);
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    final r = pages[index].record;
    final page = pages[index].page;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final buttonStyle = IconButton.styleFrom(
      iconSize: 20,
      minimumSize: const Size.square(36),
      padding: const EdgeInsets.all(6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final paper = wordBackgroundColor(context, r.text);
    return Dialog(
      key: const ValueKey('생각읽기'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: LayoutBuilder(
          builder: (context, bounds) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxWidth),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ThoughtPaperStack(
                  remaining: pages.length - index - 1,
                  paper: paper,
                  step: 3,
                  radius: 8,
                  child: Material(
                    color: paper,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 4, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (r.important)
                                const Icon(Icons.priority_high, size: 14),
                              if (r.photos.isNotEmpty)
                                const Icon(Icons.image_outlined, size: 14),
                              if (r.recordings.isNotEmpty)
                                IconButton(
                                  style: buttonStyle,
                                  tooltip: '음성 재생',
                                  icon: const Icon(Icons.mic_none),
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (context) => SimpleDialog(
                                      insetPadding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 24,
                                      ),
                                      titlePadding: const EdgeInsets.fromLTRB(
                                        24,
                                        12,
                                        8,
                                        0,
                                      ),
                                      title: Row(
                                        children: [
                                          const Expanded(child: Text('음성 재생')),
                                          IconButton(
                                            tooltip: '닫기',
                                            style: buttonStyle,
                                            iconSize: 16,
                                            icon: const Icon(Icons.close),
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ),
                                        ],
                                      ),
                                      contentPadding: const EdgeInsets.fromLTRB(
                                        24,
                                        8,
                                        24,
                                        20,
                                      ),
                                      children: [
                                        SizedBox(
                                          width: 420,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (final clip in r.recordings)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    top:
                                                        clip ==
                                                            r.recordings.first
                                                        ? 0
                                                        : 12,
                                                  ),
                                                  child: VoicePlayer(
                                                    key: ValueKey(clip.id),
                                                    dialogLayout: true,
                                                    actionStyle: buttonStyle,
                                                    load: () =>
                                                        MediaStorage.read(
                                                          clip.id,
                                                        ),
                                                    durationMs: clip.durationMs,
                                                    transcript: clip.transcript,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (r.location case final location?)
                                IconButton(
                                  style: buttonStyle,
                                  tooltip: '지도 보기',
                                  icon: const Icon(Icons.location_on_outlined),
                                  onPressed: () async {
                                    if (await loadScreen(
                                          context,
                                          location_preview.loadLibrary,
                                        ) &&
                                        context.mounted) {
                                      await location_preview
                                          .showLocationPreview(
                                            context,
                                            location,
                                          );
                                    }
                                  },
                                ),
                              ValueListenableBuilder(
                                valueListenable: memoCommentCounts,
                                builder: (context, counts, _) =>
                                    (counts[r.id] ?? 0) == 0
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        style: buttonStyle,
                                        tooltip: '댓글 보기',
                                        icon: const Icon(
                                          Icons.chat_bubble_outline,
                                        ),
                                        onPressed: () =>
                                            showMemoComments(context, r.id),
                                      ),
                              ),
                              const Spacer(),
                              IconButton(
                                style: buttonStyle,
                                tooltip: '닫기',
                                iconSize: 15,
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: IndexedStack(
                                index: index,
                                alignment: Alignment.topLeft,
                                children: [
                                  for (var i = 0; i < pages.length; i++)
                                    NotificationListener<
                                      ScrollMetricsNotification
                                    >(
                                      onNotification: (n) {
                                        _updateOverflow(i, n.metrics);
                                        return false;
                                      },
                                      child:
                                          NotificationListener<
                                            ScrollNotification
                                          >(
                                            onNotification: (n) {
                                              _updateOverflow(i, n.metrics);
                                              return false;
                                            },
                                            child: SelectionArea(
                                              child: SingleChildScrollView(
                                                primary: false,
                                                child: DocumentMarkup(
                                                  text: pages[i].page.text,
                                                  links: pages[i].page.links,
                                                  formatting: false,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: _moreBelow[index] == true
                                      ? const Icon(
                                          Icons.keyboard_arrow_down,
                                          size: 17,
                                          semanticLabel: '아래에 내용이 더 있습니다',
                                        )
                                      : null,
                                ),
                              ),
                              Text('${index + 1} / ${pages.length}'),
                              IconButton(
                                style: buttonStyle,
                                tooltip: '수정',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => Navigator.pop(context, index),
                              ),
                              if (pages.length > 1) ...[
                                IconButton(
                                  style: buttonStyle,
                                  tooltip: '이전 페이지',
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: index == 0
                                      ? null
                                      : () => setState(() => index--),
                                ),
                                IconButton(
                                  style: buttonStyle,
                                  tooltip: '다음 페이지',
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: index + 1 == pages.length
                                      ? null
                                      : () => setState(() => index++),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (page.label.isNotEmpty)
                  Positioned(
                    top: mobile ? -16 : 16,
                    left: mobile ? 0 : -84,
                    right: mobile ? 0 : null,
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: mobile ? 220 : 100,
                        ),
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
        ),
      ),
    );
  }
}

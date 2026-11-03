import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';

import 'word_badge.dart';
import 'caret_assist.dart';
import 'element_store.dart';
import 'keyboard_viewport.dart';
import 'hashtags.dart';
import 'paragraph_tag_input.dart';
import 'project_page.dart';

enum ParagraphRole { title, subtitle, body }

class Paragraph {
  const Paragraph(this.text, this.role, {this.tags = const {}});
  final String text;
  final ParagraphRole role;
  final Set<String> tags;
}

class ParagraphEditor extends StatefulWidget {
  const ParagraphEditor({
    super.key,
    this.initial = const [],
    this.projectEditing = false,
    this.projectCreation = false,
    this.available = const [],
    this.initialTags = const {},
    required this.words,
  });
  final bool projectEditing;
  final bool projectCreation;
  final List<Paragraph> available;
  final Set<String> initialTags;
  final List<Paragraph> initial;
  final List<String> words;
  @override
  State<ParagraphEditor> createState() => _ParagraphEditorState();
}

class _ParagraphEditorState extends State<ParagraphEditor> with WidgetsBindingObserver {
  final _bodyKey = GlobalKey();
  final _name = TextEditingController();
  late final TextEditingController _tags;
  bool _syncingTags = false;
  Timer? _revealTimer;
  bool _reordering = false;
  final _fieldKeys = <GlobalKey>[];

  void _scheduleReveal() {
    if (_reordering) return;
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted || !_scroll.hasClients) return;
      final active = _focus.indexWhere((focus) => focus.hasFocus);
      if (active < 0) return;
      final media = MediaQuery.of(context);
      if (media.size.width >= 760 && media.viewInsets.bottom == 0) return;
      final field = _fieldKeys[active].currentContext?.findRenderObject();
      if (field == null || !field.attached) return;
      final target = RenderAbstractViewport.of(field).getOffsetToReveal(field, 0).offset;
      final position = _scroll.position;
      _scroll.animateTo(target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    });
  }

  @override
  void didChangeMetrics() {
    _scheduleReveal();
  }
  final List<TextEditingController> _controllers = [];
  final List<ParagraphRole> _roles = [];
  final List<FocusNode> _focus = [];
  final _scroll = ScrollController();
  int _active = 0;
  bool _dirty = false;
  static const _labels = ['제목', '부제', '본문'];
  List<String> get words => widget.words.isEmpty ? starterWords : widget.words;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tags = TextEditingController(text: widget.initialTags.map((t) => '#$t').join(' '));
    for (final p in widget.projectEditing ? widget.initial : widget.initial.take(1)) {
      _add(widget.projectEditing ? p : Paragraph(p.text, ParagraphRole.body));
    }
    if (_controllers.isEmpty) _add(const Paragraph('', ParagraphRole.body));
  }

  void _moveCompletedTags(TextEditingController controller) {
    if (widget.projectEditing || _syncingTags) return;
    final completed = takeCompletedParagraphTags(controller.value);
    if (completed.tags.isEmpty) return;
    _syncingTags = true;
    try {
      final all = {
        ..._tags.text.split(RegExp(r'\s+')).map((t) => t.replaceFirst(RegExp(r'^#+'), '').toLowerCase()).where((t) => t.isNotEmpty),
        ...completed.tags,
      };
      final pending = _tags.text.endsWith(' #');
      final text = all.map((t) => '#$t').join(' ') + (pending ? ' #' : '');
      _tags.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      controller.value = completed.value;
      _dirty = true;
    } finally {
      _syncingTags = false;
    }
  }

  void _add(Paragraph p) {
    final controller = TextEditingController(text: p.text);
    _controllers.add(controller);
    controller.addListener(() {
      _moveCompletedTags(controller);
      if (mounted) setState(() {});
    });
    _roles.add(p.role);
    final focus = FocusNode();
    _fieldKeys.add(GlobalKey());
    _focus.add(focus);
    focus.addListener(() {
      if (!mounted) return;
      final index = _focus.indexOf(focus);
      if (index < 0) return;
      setState(() { if (focus.hasFocus) _active = index; });
      _scheduleReveal();
    });
  }

  Future<void> _deleteParagraph(int index) async {
    if (!widget.projectEditing) {
      final clear = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('입력 내용을 비울까요?'),
        content: const Text('작성 중인 내용과 태그를 비웁니다. 저장된 문단은 삭제하지 않습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('비우기')),
        ],
      ));
      if (clear == true && mounted) {
        setState(() { _controllers.single.clear(); _tags.clear(); _dirty = true; });
        _focus.single.requestFocus();
      }
      return;
    }
    final controller = _controllers[index];
    if (controller.text.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('문단을 삭제할까요?'),
          content: const Text('작성한 이 문단은 삭제되며 저장할 때 반영됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final current = _controllers.indexOf(controller);
    if (current < 0) return;
    final focus = _focus[current];
    final activeController = _controllers[_active];
    setState(() {
      _controllers.removeAt(current);
      _roles.removeAt(current);
      _focus.removeAt(current);
      _fieldKeys.removeAt(current);
      if (_controllers.isEmpty) _add(const Paragraph('', ParagraphRole.body));
      final retained = _controllers.indexOf(activeController);
      _active = retained >= 0 ? retained : current.clamp(0, _controllers.length - 1);
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      focus.dispose();
      if (mounted) _focus[_active].requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _name.dispose();
    _tags.dispose();
    _scroll.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _insert(String word, {bool complete = false}) {
    final c = _controllers[_active];
    final selection = c.selection;
    final prefix = complete ? completionPrefix(c.value, words) : "";
    final start =
        (selection.isValid ? selection.start : c.text.length) - prefix.length;
    final end = selection.isValid ? selection.end : start;
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, word),
      selection: TextSelection.collapsed(offset: start + word.length),
    );
    setState(() => _dirty = true);
    _focus[_active].requestFocus();
  }

  Future<void> _loadParagraph() async {
    _focus[_active].unfocus();
    var query = '';
    final picked = await showDialog<Paragraph>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('문단 찾기'),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(autofocus: true, decoration: const InputDecoration(labelText: '내용 또는 태그 검색'),
            onChanged: (value) => update(() => query = value.toLowerCase().replaceFirst(RegExp(r'^#'), ''))),
          Expanded(child: ListView(children: [
            for (final entry in widget.available.asMap().entries)
              if (entry.value.text.toLowerCase().contains(query) || entry.value.tags.any((t) => t.contains(query)))
                ListTile(key: ValueKey('pick-${entry.key}'), title: Text(entry.value.text),
                  subtitle: entry.value.tags.isEmpty ? null : Text(entry.value.tags.map((t) => '#$t').join(' ')),
                  onTap: () => Navigator.pop(context, entry.value)),
            if (widget.available.isEmpty) const ListTile(title: Text('저장된 문단이 없어요')),
          ])),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      )));
    if (picked == null || !mounted) return;
    setState(() {
      // Copy text into this project's own sentence; no link to the saved source.
      if (_controllers[_active].text.trim().isEmpty && _fieldKeys[_active].currentContext != null) {
        _controllers[_active].text = picked.text;
      } else {
        _add(Paragraph(picked.text, ParagraphRole.body));
        _active = _controllers.length - 1;
      }
      _dirty = true;
    });
    _focus[_active].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A newly appended sentence can lie outside ListView's lazy cache.
      // Build it before revealing its caret at the top of the viewport.
      if (_fieldKeys[_active].currentContext == null && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      _scheduleReveal();
    });
  }

  Future<void> _back() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('작성 중인 글을 닫을까요?'),
          content: const Text('아직 담지 않은 문단은 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 작성'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _reorderParagraph(int oldIndex, int newIndex) {
    final active = _controllers[_active];
    setState(() {
      _controllers.insert(newIndex, _controllers.removeAt(oldIndex));
      _roles.insert(newIndex, _roles.removeAt(oldIndex));
      _focus.insert(newIndex, _focus.removeAt(oldIndex));
      _fieldKeys.insert(newIndex, _fieldKeys.removeAt(oldIndex));
      _active = _controllers.indexOf(active);
      _dirty = true;
    });
  }

  Widget _paragraphField(int i) =>
                    Padding(
                      key: ObjectKey(_controllers[i]),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                              if (widget.projectEditing) ReorderableDragStartListener(
                                key: ValueKey('reorder-paragraph-$i'),
                                index: i,
                                child: const Tooltip(message: '문장 순서 변경', child: Padding(
                                  padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle),
                                )),
                              ),
                              if (widget.projectEditing) ToggleButtons(
                                direction: Axis.horizontal,
                                borderRadius: BorderRadius.circular(16),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 28,
                                ),
                                textStyle: const TextStyle(fontSize: 11),
                                isSelected: ParagraphRole.values
                                    .map((role) => role == _roles[i])
                                    .toList(),
                                onPressed: (index) {
                                  setState(() {
                                    _roles[i] = ParagraphRole.values[index];
                                    _active = i;
                                    _dirty = true;
                                  });
                                  _focus[i].requestFocus();
                                },
                                children: _labels
                                    .map(
                                      (label) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(label),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const Spacer(),
                              IconButton(
                                key: ValueKey('delete-paragraph-$i'),
                                tooltip: widget.projectEditing ? '문장 삭제' : '입력 비우기',
                                onPressed: () => _deleteParagraph(i),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              ],
                            ),
                          ],
                          CaretAssist(
                            key: _fieldKeys[i],
                            mobileViewportKey: _bodyKey,
                            controller: _controllers[i],
                            focus: _focus[i],
                            words: words,
                            onWord: (word) {
                              _active = i;
                              _insert(word, complete: true);
                            },
                            child: TextField(
                              key: ValueKey('paragraph-$i'),
                              controller: _controllers[i],
                              focusNode: _focus[i],
                              minLines: 2,
                              maxLines: null,
                              onTap: () => setState(() {
                                _active = i;
                                _scheduleReveal();
                              }),
                              onChanged: (_) => setState(() {
                                _active = i;
                                _dirty = true;
                              }),
                              style: TextStyle(
                                fontSize: _roles[i] == ParagraphRole.title
                                    ? 28
                                    : _roles[i] == ParagraphRole.subtitle
                                    ? 21
                                    : 16,
                                fontWeight: _roles[i] == ParagraphRole.body
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                                height: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText: i == 0
                                    ? '단어 하나로 시작해보세요'
                                    : '다음 생각을 이어보세요',
                                labelText: widget.projectEditing ? '문장 ${i + 1}' : '문단',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

  @override
  Widget build(BuildContext context) {
    final rawMedia = MediaQuery.of(context);
    final media = rawMedia.copyWith(viewInsets: rawMedia.viewInsets.copyWith(
      bottom: effectiveKeyboardInset(rawMedia),
    ));
    final mobile = media.size.width < 760 || media.viewInsets.bottom > 0;
    final assistSpace = mobile && _focus.any((f) => f.hasFocus)
        ? mobileAssistHeight(media) : 0.0;
    final colors = Theme.of(context).colorScheme;
    final hasText = _controllers.any((c) => (widget.projectEditing ? c.text : parseTaggedInput(c.text).text).trim().isNotEmpty);
    return MediaQuery(
      data: media,
      child: PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
            tooltip: '돌아가기',
          ),
          title: Text(widget.projectEditing ? (widget.projectCreation ? '프로젝트 생성' : '프로젝트 편집') : '문단 쓰기'),
          actions: [
            TextButton(
                onPressed: hasText
                    ? () {
                        _focus[_active].unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('미리보기')),
                              body: SafeArea(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 800,
                                    ),
                                    child: ListView(
                                      padding: const EdgeInsets.all(24),
                                      children: [
                                        for (
                                          var i = 0;
                                          i < _controllers.length;
                                          i++
                                        )
                                          if (_controllers[i].text
                                              .trim()
                                              .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 20,
                                              ),
                                              child: ElementText(
                                                widget.projectEditing ? _controllers[i].text : parseTaggedInput(_controllers[i].text).text,
                                                style: TextStyle(
                                                  height: 1.7,
                                                  fontSize:
                                                      _roles[i] ==
                                                          ParagraphRole.title
                                                      ? 30
                                                      : _roles[i] ==
                                                            ParagraphRole
                                                                .subtitle
                                                      ? 22
                                                      : 16,
                                                  fontWeight:
                                                      _roles[i] ==
                                                          ParagraphRole.body
                                                      ? FontWeight.normal
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    : null,
                child: const Text('미리보기'),
              ),

            TextButton(
              onPressed: hasText
                  ? () {
                      final result = [
                        for (var i = 0; i < _controllers.length; i++)
                          if (_controllers[i].text.trim().isNotEmpty)
                            if (widget.projectEditing)
                              Paragraph(_controllers[i].text, _roles[i])
                            else
                              Paragraph(parseTaggedInput(_controllers[i].text).text, ParagraphRole.body,
                                tags: {...parseTaggedInput(_controllers[i].text).tags,
                                  ..._tags.text.split(RegExp(r'\s+')).map((t) => t.replaceFirst(RegExp(r'^#'), '').toLowerCase()).where((t) => t.isNotEmpty)}),
                      ];
                      if (widget.projectCreation) {
                        final title = _name.text.trim();
                        final fallback = result.firstWhere((p) => p.role == ParagraphRole.title, orElse: () => result.first).text.split('\n').first;
                        Navigator.pop(context, WritingProject(result, widget.words, name: title.isEmpty ? fallback : title));
                      } else {
                        Navigator.pop(context, result);
                      }
                    }
                  : null,
              child: Text(widget.projectCreation ? '프로젝트 만들기' : '저장'),
            ),
          ],
        ),
        body: SafeArea(
          child: Container(
            key: _bodyKey,
            child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: LayoutBuilder(builder: (context, constraints) => CustomScrollView(
                key: const ValueKey('paragraph-scroll'),
                controller: _scroll,
                slivers: [SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20,
                    assistSpace > 0 ? math.max(20 + assistSpace, constraints.maxHeight - 72) : 20),
                  sliver: SliverMainAxisGroup(slivers: [
                  SliverToBoxAdapter(child: Column(children: [
                  if (widget.projectCreation) TextField(key: const ValueKey('project-name'), controller: _name,
                    decoration: const InputDecoration(labelText: '프로젝트 이름', helperText: '비워두면 제목 또는 첫 문장을 사용합니다.'),
                    onChanged: (_) => setState(() => _dirty = true)),
                  if (widget.projectEditing) Align(alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(onPressed: _loadParagraph, icon: const Icon(Icons.search), label: const Text('문단 찾기'))),
                  ])),
                  if (widget.projectEditing) SliverReorderableList(
                    itemCount: _controllers.length,
                    itemBuilder: (context, index) => _paragraphField(index),
                    onReorderItem: _reorderParagraph,
                    onReorderStart: (_) { _revealTimer?.cancel(); _reordering = true; },
                    onReorderEnd: (_) { _reordering = false; },
                    proxyDecorator: (child, index, animation) => Material(elevation: 6, child: child),
                  ) else SliverList(delegate: SliverChildBuilderDelegate(
                    (context, index) => _paragraphField(index), childCount: _controllers.length)),
                  SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!widget.projectEditing) TextField(
                    key: const ValueKey('paragraph-tags'), controller: _tags,
                    inputFormatters: const [HashtagInputFormatter()],
                    decoration: const InputDecoration(labelText: '태그', hintText: '#독서 #아이디어'),
                    onChanged: (_) => setState(() => _dirty = true)),
                  if (widget.projectEditing) OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _add(const Paragraph('', ParagraphRole.body));
                        _active = _controllers.length - 1;
                      });
                      _focus.last.requestFocus();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _focus.last.requestFocus();
                        _scheduleReveal();
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('다음 문단'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '저장을 누르면 문단이 보관됩니다.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  ])),
                  ]),
                )],
              )),
            ),
          ),
          ),
        ),
      ),
      ),
    );
  }
}

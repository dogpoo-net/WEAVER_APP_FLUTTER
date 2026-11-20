import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'label_links.dart';
import 'memo_boxes.dart';

typedef DocumentAiRequest = Future<Map<String, dynamic>> Function(
  Map<String, Object?> input,
);
typedef DocumentAiThought = ({
  String id,
  String title,
  String text,
  Set<String> tags,
});
const _thoughtEmbed = 'weaver-ai-thought';

class DocumentAiPanel extends StatefulWidget {
  const DocumentAiPanel({
    super.key,
    required this.thoughts,
    required this.request,
    required this.onInsert,
    this.thoughtForDrag,
  });

  final List<DocumentAiThought> thoughts;
  final DocumentAiRequest request;
  final bool Function(String) onInsert;
  final DocumentAiThought? Function(InlineLinkDrag)? thoughtForDrag;

  @override
  State<DocumentAiPanel> createState() => _DocumentAiPanelState();
}

class _DocumentAiPanelState extends State<DocumentAiPanel> {
  final _material = quill.QuillController.basic();
  final _editor = GlobalKey<quill.EditorState>();
  final _input = GlobalKey();
  final _instruction = TextEditingController();
  final _tokens = <String, DocumentAiThought>{};
  final _boxes = <MemoBox>{};
  final _tags = <String>{};
  var _nextToken = 0;
  var _query = '', _length = 'medium';
  bool _busy = false, _showResult = false;
  String? _result, _error;

  bool get _mobile => widget.thoughtForDrag == null;

  @override
  void initState() {
    super.initState();
    _material.addListener(_materialChanged);
  }

  void _materialChanged() => setState(() {});

  String _sourceMaterial() {
    final text = StringBuffer();
    for (final op in _material.document.toDelta().toJson()) {
      final insert = op['insert'];
      if (insert is String) {
        text.write(insert);
      } else if (insert is Map) {
        final thought = _tokens[insert[_thoughtEmbed]];
        if (thought != null) text.write(' ${thought.text.trim()} ');
      }
    }
    return text.toString().trim();
  }

  int? _tokenPosition(String token) {
    var offset = 0;
    for (final op in _material.document.toDelta().toJson()) {
      final insert = op['insert'];
      if (insert is Map && insert[_thoughtEmbed] == token) return offset;
      offset += insert is String ? insert.length : 1;
    }
    return null;
  }

  int _dropPosition(Offset global) {
    final render = _editor.currentState?.renderEditor;
    return (render?.getPositionForOffset(global).offset ??
            _material.document.length - 1)
        .clamp(0, _material.document.length - 1);
  }

  void _putToken(String token, int offset) {
    _material.replaceText(
      offset,
      0,
      quill.Embeddable(_thoughtEmbed, token),
      TextSelection.collapsed(offset: offset + 1),
      ignoreFocus: true,
    );
  }

  void _add(DocumentAiThought thought, int offset) {
    if (_busy) return;
    final token = '${_nextToken++}';
    _tokens[token] = thought;
    _putToken(token, offset);
  }

  void _move(String token, int offset) {
    final from = _tokenPosition(token);
    if (from == null || from == offset || from + 1 == offset) return;
    _material.replaceText(from, 1, '', null, ignoreFocus: true);
    _putToken(token, offset > from ? offset - 1 : offset);
  }

  void _removeOutside(String token, Offset drop) {
    final input = _input.currentContext?.findRenderObject() as RenderBox?;
    if (input == null ||
        (Offset.zero & input.size).contains(input.globalToLocal(drop)))
      return;
    final position = _tokenPosition(token);
    if (position != null) {
      _material.replaceText(position, 1, '', null, ignoreFocus: true);
    }
  }

  Future<void> _generate() async {
    if (_busy) return;
    final material = _sourceMaterial();
    if (material.isEmpty) return;
    if (material.length > 20000) {
      setState(() => _error = '자료 전체를 20,000자 이하로 줄여주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.request({
        'material': material,
        'instruction': _instruction.text.trim(),
        'length': _length,
      });
      if (!mounted) return;
      final text = response['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const FormatException('AI가 완성된 글을 반환하지 않았습니다.');
      }
      setState(() {
        _result = text.trim();
        _showResult = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('복사했어요.')));
  }

  @override
  void dispose() {
    _material.removeListener(_materialChanged);
    _material.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Widget _mobileThoughts() {
    final tags =
        widget.thoughts.expand((thought) => thought.tags).toSet().toList()
          ..sort();
    final matches = widget.thoughts.where((thought) {
      final inFilter =
          (_boxes.isEmpty && _tags.isEmpty) ||
          _boxes.any((box) => box.elementIds.contains(thought.id)) ||
          thought.tags.any(_tags.contains);
      return inFilter && thought.text.toLowerCase().contains(_query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '생각 검색',
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onChanged: (query) =>
              setState(() => _query = query.trim().toLowerCase()),
        ),
        SizedBox(
          height: 100,
          child: matches.isEmpty
              ? const Center(child: Text('담을 생각이 없습니다.'))
              : ListView.builder(
                  primary: false,
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final thought = matches[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        thought.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.add, size: 18),
                      enabled: !_busy,
                      onTap: () => _add(thought, _material.document.length - 1),
                    );
                  },
                ),
        ),
        _filterRow(Icons.inventory_2_outlined, [
          for (final box in memoBoxes)
            FilterChip(
              label: Text(box.name),
              selected: _boxes.contains(box),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _boxes.add(box);
                } else {
                  _boxes.remove(box);
                }
              }),
            ),
        ]),
        _filterRow(Icons.tag, [
          for (final tag in tags)
            FilterChip(
              label: Text('#$tag'),
              selected: _tags.contains(tag),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _tags.add(tag);
                } else {
                  _tags.remove(tag);
                }
              }),
            ),
        ]),
      ],
    );
  }

  Widget _filterRow(IconData icon, List<Widget> items) => SizedBox(
    height: 32,
    child: Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
            separatorBuilder: (_, _) => const SizedBox(width: 4),
          ),
        ),
      ],
    ),
  );

  Widget _badge(String token) {
    final thought = _tokens[token];
    if (thought == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final badge = Container(
      constraints: const BoxConstraints(maxWidth: 170),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        thought.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colors.onSecondaryContainer),
      ),
    );
    if (_busy) return badge;
    final feedback = Material(color: Colors.transparent, child: badge);
    if (_mobile) {
      return LongPressDraggable<_ThoughtDrag>(
        data: _ThoughtDrag(token),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        onDraggableCanceled: (_, offset) => _removeOutside(token, offset),
        child: badge,
      );
    }
    return Draggable<_ThoughtDrag>(
      data: _ThoughtDrag(token),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      onDraggableCanceled: (_, offset) => _removeOutside(token, offset),
      child: badge,
    );
  }

  static final _filledBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide.none,
  );

  Color get _fieldFill =>
      Theme.of(context).inputDecorationTheme.fillColor ??
      Theme.of(context).colorScheme.surfaceContainerHighest;

  Widget _materialInput(double height) {
    _material.readOnly = _busy;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          !_busy &&
          switch (details.data) {
            _ThoughtDrag(:final token) => _tokenPosition(token) != null,
            InlineLinkDrag drag => widget.thoughtForDrag?.call(drag) != null,
            _ => false,
          },
      onAcceptWithDetails: (details) {
        final offset = _dropPosition(details.offset);
        switch (details.data) {
          case _ThoughtDrag(:final token):
            _move(token, offset);
          case InlineLinkDrag drag:
            final thought = widget.thoughtForDrag?.call(drag);
            if (thought != null) _add(thought, offset);
        }
      },
      builder: (context, candidates, _) => Container(
        key: _input,
        height: height,
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? _fieldFill
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: quill.QuillEditor.basic(
          controller: _material,
          config: quill.QuillEditorConfig(
            editorKey: _editor,
            placeholder: _mobile ? '생각을 담거나 자료를 입력하세요' : '생각을 끌어놓거나 자료를 입력하세요',
            padding: const EdgeInsets.all(8),
            autoFocus: false,
            expands: true,
            embedBuilders: [_ThoughtEmbedBuilder(_badge)],
          ),
        ),
      ),
    );
  }

  Widget _tab(String title, {required bool selected, VoidCallback? onPressed}) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        enabled: onPressed != null,
        child: InkWell(
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? colors.primary : colors.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            child: Center(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: onPressed == null
                      ? colors.onSurface.withValues(alpha: .38)
                      : selected
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lengthMenu() {
    const choices = {'short': '짤막', 'medium': '중간', 'long': '길게'};
    return MenuAnchor(
      style: const MenuStyle(
        alignment: AlignmentDirectional.topEnd,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      ),
      alignmentOffset: const Offset(2, 0),
      menuChildren: [
        for (final entry in choices.entries)
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(92, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: () => setState(() => _length = entry.key),
            child: Text(entry.value),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: '문장 길이 선택',
        child: InkWell(
          onTap: _busy
              ? null
              : () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(choices[_length]!, style: const TextStyle(fontSize: 13)),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              role: SemanticsRole.tabBar,
              child: SizedBox(
                height: 34,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tab(
                      'AI 문장 생성',
                      selected: !_showResult,
                      onPressed: () => setState(() => _showResult = false),
                    ),
                    _tab(
                      '결과',
                      selected: _showResult,
                      onPressed: _result == null
                          ? null
                          : () => setState(() => _showResult = true),
                    ),
                  ],
                ),
              ),
            ),
            if ((_showResult ? _result : null) case final text?) ...[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(text),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => _copy(text),
                      child: const Text('복사'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (widget.onInsert(text) && _mobile)
                          Navigator.pop(context);
                      },
                      child: const Text('커서 아래에 삽입'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Expanded(
                child: _mobile
                    ? ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        children: [
                          _mobileThoughts(),
                          const SizedBox(height: 6),
                          _materialInput(
                            (constraints.maxHeight * .42).clamp(130.0, 400.0),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: LayoutBuilder(
                          builder: (context, input) =>
                              _materialInput(input.maxHeight),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _instruction,
                      readOnly: _busy,
                      maxLength: 100,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _fieldFill,
                        border: _filledBorder,
                        enabledBorder: _filledBorder,
                        focusedBorder: _filledBorder,
                        labelText: '프롬프트',
                        hintText: '톤, 느낌, 목적',
                        counterText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('문장 길이'),
                        const SizedBox(width: 6),
                        _lengthMenu(),
                      ],
                    ),
                    if (_error case final error?)
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _busy || _material.document.length <= 1
                      ? null
                      : _generate,
                  child: Text(_busy ? '생성 중...' : '생성'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThoughtDrag {
  const _ThoughtDrag(this.token);
  final String token;
}

class _ThoughtEmbedBuilder extends quill.EmbedBuilder {
  const _ThoughtEmbedBuilder(this.badge);
  final Widget Function(String) badge;

  @override
  String get key => _thoughtEmbed;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) =>
      badge(embedContext.node.value.data as String);
}

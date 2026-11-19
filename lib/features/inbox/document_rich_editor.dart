import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'document_syntax.dart';
import 'canvas_link_text.dart';
import 'document_code_block.dart';
import 'element_binding.dart';

const _marks = {
  '**': 'bold',
  '//': 'italic',
  '__': 'underline',
  '--': 'strike',
};

/// Project a supported source line into Quill inserts, without updating source.
List<Map<String, Object>> _decodeLine(String line) {
  if (documentCodeBlocks(line).isNotEmpty) {
    final code = documentCodeBody(line);
    return [
      if (code.isNotEmpty) {'insert': code},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ];
  }
  final heading = projectHeading.firstMatch(line);
  final marker = heading == null ? documentListMarker.firstMatch(line) : null;
  final text =
      heading?.group(2) ?? (marker == null ? line : line.substring(marker.end));
  final ops = <Map<String, Object>>[];
  void insert(String value, Map<String, Object> attrs) {
    if (value.isNotEmpty)
      ops.add({'insert': value, if (attrs.isNotEmpty) 'attributes': attrs});
  }

  void inline(String input, Map<String, Object> attrs) {
    var start = 0;
    for (var i = 0; i + 1 < input.length; i++) {
      final marker = input.substring(i, i + 2);
      final attr = _marks[marker];
      if (attr == null || (marker == '//' && i > 0 && input[i - 1] == ':'))
        continue;
      final end = input.indexOf(marker, i + 2);
      if (end <= i + 2) continue;
      insert(input.substring(start, i), attrs);
      inline(input.substring(i + 2, end), {...attrs, attr: true});
      i = end + 1;
      start = end + 2;
    }
    insert(input.substring(start), attrs);
  }

  inline(text, const {});
  insert('\n', {
    if (heading != null) 'header': 7 - heading.group(1)!.length,
    if (marker != null) 'list': marker.group(2) == null ? 'bullet' : 'ordered',
  });
  return ops;
}

List<String> _encodeLines(quill.Document doc) {
  final lines = <String>[];
  final text = StringBuffer();
  var active = <String>[];
  var number = 0;
  for (final op in doc.toDelta().toJson()) {
    final insert = op['insert'];
    if (insert is! String) continue;
    final attrs = op['attributes'] as Map? ?? const {};
    final marks = [
      for (final entry in _marks.entries)
        if (attrs[entry.value] == true) entry.key,
    ];
    final pieces = insert.split('\n');
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].isNotEmpty) {
        var shared = 0;
        while (shared < active.length &&
            shared < marks.length &&
            active[shared] == marks[shared]) {
          shared++;
        }
        text.writeAll(active.skip(shared).toList().reversed);
        text.writeAll(marks.skip(shared));
        active = marks;
        text.write(pieces[i]);
      }
      if (i + 1 < pieces.length) {
        text.writeAll(active.reversed);
        active = [];
        final header = attrs['header'];
        final delimiter =
            header is int && header >= 1 && header <= 5 && text.isNotEmpty
            ? '=' * (7 - header)
            : '';
        final list = attrs['list'];
        number = list == 'ordered' ? number + 1 : 0;
        final prefix = list == 'ordered'
            ? '$number. '
            : list == 'bullet'
            ? '- '
            : '';
        lines.add(
          attrs['code-block'] == true
              ? '<code>$text</code>'
              : '$prefix$delimiter$text$delimiter',
        );
        text.clear();
      }
    }
  }
  return lines;
}

class _Section {
  _Section(this.source, {required this.protected});

  String source;
  final bool protected;
  final key = GlobalKey();
  quill.QuillController? controller;
  FocusNode? focus;
  ScrollController? scroll;
  List<String> projected = const [];

  void initialize() {
    if (protected) return;
    final document = quill.Document.fromJson([
      for (final line in source.split('\n')) ..._decodeLine(line),
    ]);
    projected = _encodeLines(document);
    controller = quill.QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    focus = FocusNode();
    scroll = ScrollController();
  }

  void dispose() {
    controller?.dispose();
    focus?.dispose();
    scroll?.dispose();
  }
}

/// Quill edits supported text. Existing links and block syntax stay in source
/// ranges that are never round-tripped through Delta.
class DocumentRichEditor extends StatefulWidget {
  const DocumentRichEditor({
    super.key,
    required this.source,
    required this.links,
    required this.onPatch,
    required this.onLinkHover,
  });

  final String source;
  final List<ElementBinding> links;
  final void Function(int start, int end, String replacement) onPatch;
  final ValueChanged<String?> onLinkHover;

  @override
  State<DocumentRichEditor> createState() => _DocumentRichEditorState();
}

class _DocumentRichEditorState extends State<DocumentRichEditor> {
  final _sections = <_Section>[];
  _Section? _active;

  @override
  void initState() {
    super.initState();
    final editableCodeLines = {
      for (final block in documentCodeBlocks(widget.source))
        if (!block.group(0)!.contains('\n')) block.start,
    };
    final code = codeMarkup
        .allMatches(widget.source)
        .where((match) => !editableCodeLines.contains(match.start))
        .toList();
    final group = <String>[];
    bool? protected;
    var offset = 0;
    void finish() {
      if (group.isEmpty) return;
      _sections.add(_Section(group.join('\n'), protected: protected!));
      group.clear();
    }

    for (final line in widget.source.split('\n')) {
      final end = offset + line.length;
      final isProtected =
          code.any((match) => match.start <= end && match.end > offset) ||
          widget.links.any((link) => link.start <= end && link.end > offset) ||
          (documentListMarker.firstMatch(line)?.group(1)?.isNotEmpty ??
              false) ||
          line.startsWith('|') ||
          line.contains('[[') ||
          documentFootnoteReference.hasMatch(line) ||
          documentEditorComment.hasMatch(line);
      if (isProtected != protected) finish();
      protected = isProtected;
      group.add(line);
      offset = end + 1;
    }
    finish();
    if (_sections.every((section) => section.protected)) {
      _sections.add(_Section('', protected: false));
      _appendSectionOnEdit = true;
    }
    for (final section in _sections) {
      section.initialize();
      section.controller?.addListener(() => _edited(section));
      section.focus?.addListener(() {
        if (mounted && section.focus!.hasFocus && _active != section) {
          setState(() => _active = section);
        }
      });
    }
    _active = _sections.where((section) => !section.protected).firstOrNull;
  }

  bool _appendSectionOnEdit = false;

  void _edited(_Section section) {
    final next = _encodeLines(section.controller!.document);
    final before = section.projected;
    var start = 0;
    while (start < before.length &&
        start < next.length &&
        before[start] == next[start]) {
      start++;
    }
    if (start == before.length && start == next.length) return;
    var oldEnd = before.length;
    var newEnd = next.length;
    while (oldEnd > start &&
        newEnd > start &&
        before[oldEnd - 1] == next[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final sourceLines = section.source.split('\n');
    final updated = [
      ...sourceLines.take(start),
      ...next.getRange(start, newEnd),
      ...sourceLines.skip(oldEnd),
    ].join('\n');
    var offset = 0;
    for (final other in _sections) {
      if (identical(other, section)) break;
      offset += other.source.length + 1;
    }
    final previousLength = section.source.length;
    section.source = updated;
    section.projected = next;
    if (mounted) setState(() {});
    if (_appendSectionOnEdit) {
      _appendSectionOnEdit = false;
      widget.onPatch(offset - 1, offset - 1, '\n$updated');
    } else {
      widget.onPatch(offset, offset + previousLength, updated);
    }
  }

  @override
  void dispose() {
    for (final section in _sections) {
      section.dispose();
    }
    super.dispose();
  }

  void _toggle(quill.Attribute attribute) {
    final section = _active;
    if (section == null) return;
    final controller = section.controller!;
    final current = controller.getSelectionStyle().attributes[attribute.key];
    controller.formatSelection(
      current?.value == attribute.value
          ? quill.Attribute.clone(attribute, null)
          : attribute,
    );
    section.focus!.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final headings = <({String title, _Section section, int offset})>[];
    for (final section in _sections) {
      var offset = 0;
      for (final line in section.projected) {
        final match = projectHeading.firstMatch(line);
        if (match != null)
          headings.add((
            title: match.group(2)!,
            section: section,
            offset: offset,
          ));
        for (final op in _decodeLine(line)) {
          offset += (op['insert'] as String).length;
        }
      }
    }
    final sectionWidgets = <Widget>[];
    var sectionStart = 0;
    for (final section in _sections) {
      final sectionEnd = sectionStart + section.source.length;
      sectionWidgets.add(
        section.protected
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: _ProtectedDocumentSource(
                  source: section.source,
                  links: [
                    for (final link in widget.links)
                      if (link.start >= sectionStart && link.end <= sectionEnd)
                        ElementBinding(
                          link.id,
                          link.start - sectionStart,
                          link.end - sectionStart,
                        ),
                  ],
                  onLinkHover: widget.onLinkHover,
                ),
              )
            : _QuillEditorBlock(section: section, key: section.key),
      );
      sectionStart = sectionEnd + 1;
    }
    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            children: [
              _formatButton('코드 블록', Icons.code, quill.Attribute.codeBlock),
              _formatButton(
                '번호 목록',
                Icons.format_list_numbered,
                quill.Attribute.ol,
              ),
              _formatButton(
                '글머리표',
                Icons.format_list_bulleted,
                quill.Attribute.ul,
              ),
              _formatButton('굵게', Icons.format_bold, quill.Attribute.bold),
              _formatButton('기울임', Icons.format_italic, quill.Attribute.italic),
              _formatButton(
                '밑줄',
                Icons.format_underlined,
                quill.Attribute.underline,
              ),
              _formatButton(
                '취소선',
                Icons.strikethrough_s,
                quill.Attribute.strikeThrough,
              ),
              PopupMenuButton<int>(
                tooltip: '제목 단계',
                icon: const Icon(Icons.title),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 0, child: Text('본문')),
                  for (var level = 1; level <= 5; level++)
                    PopupMenuItem(value: level, child: Text('제목 $level')),
                ],
                onSelected: (level) {
                  final section = _active;
                  if (section == null) return;
                  section.controller!.formatSelection(
                    quill.HeaderAttribute(level: level == 0 ? null : level),
                  );
                  section.focus!.requestFocus();
                },
              ),
              if (headings.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: '목차',
                  icon: const Icon(Icons.list),
                  itemBuilder: (_) => [
                    for (var i = 0; i < headings.length; i++)
                      PopupMenuItem(value: i, child: Text(headings[i].title)),
                  ],
                  onSelected: (index) {
                    final entry = headings[index];
                    final target = entry.section.key.currentContext;
                    if (target != null) Scrollable.ensureVisible(target);
                    final controller = entry.section.controller!;
                    controller.updateSelection(
                      TextSelection.collapsed(
                        offset: entry.offset.clamp(
                          0,
                          controller.document.length - 1,
                        ),
                      ),
                      quill.ChangeSource.local,
                    );
                    entry.section.focus!.requestFocus();
                  },
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sectionWidgets,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatButton(
    String label,
    IconData icon,
    quill.Attribute attribute,
  ) => IconButton(
    tooltip: label,
    icon: Icon(icon),
    onPressed: () => _toggle(attribute),
  );
}

class _QuillEditorBlock extends StatelessWidget {
  const _QuillEditorBlock({super.key, required this.section});
  final _Section section;

  @override
  Widget build(BuildContext context) => quill.QuillEditor.basic(
    controller: section.controller!,
    focusNode: section.focus!,
    scrollController: section.scroll!,
    config: quill.QuillEditorConfig(
      scrollable: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      customStyles: quill.DefaultStyles(
        code: quill.DefaultTextBlockStyle(
          documentCodeStyle(context),
          const quill.HorizontalSpacing(10, 10),
          const quill.VerticalSpacing(4, 4),
          const quill.VerticalSpacing(2, 2),
          documentCodeDecoration(context),
        ),
      ),
    ),
  );
}

class _ProtectedDocumentSource extends StatelessWidget {
  const _ProtectedDocumentSource({
    required this.source,
    required this.links,
    required this.onLinkHover,
  });
  final String source;
  final List<ElementBinding> links;
  final ValueChanged<String?> onLinkHover;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    Widget textSegment(int start, int end) {
      final segmentLinks = [
        for (final link in links)
          if (link.start >= start && link.end <= end)
            ElementBinding(link.id, link.start - start, link.end - start),
      ];
      final text = source.substring(start, end);
      return segmentLinks.isEmpty
          ? SelectableText(text)
          : SelectionArea(
              child: CanvasLinkText(
                text: text,
                links: segmentLinks,
                enabled: true,
                onLinkHover: onLinkHover,
              ),
            );
    }

    var offset = 0;
    for (final block in documentCodeBlocks(source)) {
      if (offset < block.start) {
        children.add(textSegment(offset, block.start));
      }
      children.add(
        SelectionArea(
          child: DocumentCodeBlock(documentCodeBody(block.group(0)!)),
        ),
      );
      offset = block.end;
      if (offset < source.length && source[offset] == '\n') offset++;
    }
    if (offset < source.length)
      children.add(textSegment(offset, source.length));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

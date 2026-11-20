import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' show Delta;

import 'document_syntax.dart';
import 'document_visual_block.dart';
import 'document_line_shortcuts.dart';
import 'document_table.dart';
import 'document_diagnostics.dart';
import 'canvas_link_text.dart';
import 'document_code_block.dart';
import 'element_binding.dart';

const _dashBullet = quill.ListAttribute('dash');
const _footnoteEmbed = 'weaver-footnote';

const _marks = {
  '**': 'bold',
  '//': 'italic',
  '__': 'underline',
  '--': 'strike',
};

const _codeLanguagePrefix = '[lang:';
const _emptyCodeLanguageLine = '[lang: ]';
final _codeLanguageLine = RegExp(r'^\[lang:[ \t]*([^"<>\]\r\n]*)\]$');
const _codeLineAttributes = {'code-block': true};

String _languageLine(String? language) => '[lang: ${language ?? ''}]';
String _readLanguageLine(String line) =>
    _codeLanguageLine.firstMatch(line)?.group(1)?.trim() ?? '';

quill.AlignAttribute? _sourceAlignment(String line) {
  if (line.length <= 2 || !line.startsWith('|') || !line.endsWith('|')) {
    return null;
  }
  final leading = line[1] == ' ';
  final trailing = line[line.length - 2] == ' ';
  return quill.AlignAttribute(
    leading ? (trailing ? 'center' : 'right') : 'left',
  );
}

String _alignSource(String value, Object? alignment) => switch (alignment) {
  'left' => '|$value |',
  'center' => '| $value |',
  'right' => '| $value|',
  _ => value,
};

/// Project a supported source line into Quill inserts, without updating source.
List<Map<String, Object>> _decodeLine(
  String line, {
  bool showCodeLanguage = false,
  List<int>? sourceOffsets,
}) {
  if (documentCodeBlocks(line).isNotEmpty) {
    final code = documentCodeBody(line);
    final start = documentCodeOpening.matchAsPrefix(line)!.end;
    for (var i = 0; i < code.length; i++) {
      sourceOffsets?.add(start + i);
    }
    return [
      if (showCodeLanguage) ...[
        {'insert': _languageLine(documentCodeLanguage(line))},
        {'insert': '\n', 'attributes': _codeLineAttributes},
      ],
      if (code.isNotEmpty) {'insert': code},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ];
  }
  final heading = projectHeading.firstMatch(line);
  final marker = heading == null ? documentListMarker.firstMatch(line) : null;
  final alignment = _sourceAlignment(line);
  final text = alignment != null
      ? line.substring(1, line.length - 1).trim()
      : heading?.group(2) ??
            (marker == null ? line : line.substring(marker.end));
  final ops = <Map<String, Object>>[];
  void insert(String value, Map<String, Object> attrs) {
    if (value.isNotEmpty)
      ops.add({'insert': value, if (attrs.isNotEmpty) 'attributes': attrs});
  }

  void inline(String input, Map<String, Object> attrs, int sourceStart) {
    void emit(int start, int end) {
      insert(input.substring(start, end), attrs);
      for (var i = start; i < end; i++) {
        sourceOffsets?.add(sourceStart + i);
      }
    }

    var start = 0;
    for (var i = 0; i + 1 < input.length; i++) {
      final code = documentCodeOpening.matchAsPrefix(input, i);
      if (code != null) {
        final close = input.indexOf('</code>', code.end);
        if (close >= 0) {
          i = close + 6;
          continue;
        }
      }
      if (input.startsWith('[[', i)) {
        final close = input.indexOf(']]', i + 2);
        if (close >= 0) {
          i = close + 1;
          continue;
        }
      }
      final footnote = documentFootnoteReference.matchAsPrefix(input, i);
      if (footnote != null) {
        emit(start, i);
        ops.add({
          'insert': {_footnoteEmbed: footnote.group(1)!},
          if (attrs.isNotEmpty) 'attributes': attrs,
        });
        sourceOffsets?.add(sourceStart + i);
        start = footnote.end;
        i = start - 1;
        continue;
      }
      final marker = input.substring(i, i + 2);
      final attr = _marks[marker];
      if (attr == null || (marker == '//' && i > 0 && input[i - 1] == ':'))
        continue;
      final end = input.indexOf(marker, i + 2);
      if (end <= i + 2) continue;
      emit(start, i);
      inline(input.substring(i + 2, end), {
        ...attrs,
        attr: true,
      }, sourceStart + i + 2);
      i = end + 1;
      start = end + 2;
    }
    emit(start, input.length);
  }

  final textStart = alignment != null
      ? 1 +
            line.substring(1, line.length - 1).length -
            line.substring(1, line.length - 1).trimLeft().length
      : (heading?.group(1)!.length ?? marker?.end ?? 0);
  inline(text, const {}, textStart);
  insert('\n', {
    if (alignment != null) 'align': alignment.value!,
    if (heading != null) 'header': 7 - heading.group(1)!.length,
    if (marker != null)
      'list': switch (marker.group(3)) {
        '–' => _dashBullet.value!,
        '-' => 'bullet',
        _ => 'ordered',
      },
  });
  return ops;
}

List<String> _encodeLines(
  quill.Document doc, {
  List<int>? missingLanguageOffsets,
  List<int>? contentOffsets,
}) {
  final lines = <String>[];
  final text = StringBuffer();
  var active = <String>[];
  var number = 0;
  var offset = 0;
  var lineStart = 0;
  var inCode = false;
  int? pendingLanguageOffset;
  var language = '';
  for (final op in doc.toDelta().toJson()) {
    final value = op['insert'];
    final footnote = value is Map ? value[_footnoteEmbed] : null;
    final insert = footnote is String ? '[^$footnote]' : value;
    if (insert is! String) continue;
    final attrs = op['attributes'] as Map? ?? const {};
    final marks = [
      for (final entry in _marks.entries)
        if (attrs[entry.value] == true) entry.key,
    ];
    final pieces = insert.split('\n');
    for (var i = 0; i < pieces.length; i++) {
      offset += footnote is String ? 1 : pieces[i].length;
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
        final prefix = switch (list) {
          'ordered' => '$number. ',
          'bullet' => '- ',
          'dash' => '– ',
          _ => '',
        };
        final isCode = attrs['code-block'] == true;
        final value = text.toString();
        if (isCode && !inCode) {
          language = '';
          if (!value.startsWith(_codeLanguagePrefix)) {
            missingLanguageOffsets?.add(lineStart);
          }
        }
        if (!isCode && pendingLanguageOffset != null) {
          contentOffsets?.add(pendingLanguageOffset);
          lines.add('${_codeOpeningFor(language)}</code>');
          pendingLanguageOffset = null;
        }
        if (isCode && !inCode && value.startsWith(_codeLanguagePrefix)) {
          pendingLanguageOffset = lineStart;
          language = _readLanguageLine(value);
        } else {
          pendingLanguageOffset = null;
          contentOffsets?.add(lineStart);
          lines.add(
            isCode
                ? '${_codeOpeningFor(language)}$value</code>'
                : delimiter.isEmpty && prefix.isEmpty
                ? _alignSource(value, attrs['align'])
                : '$prefix$delimiter$value$delimiter',
          );
        }
        inCode = isCode;
        lineStart = ++offset;
        text.clear();
      }
    }
  }
  if (pendingLanguageOffset != null) {
    contentOffsets?.add(pendingLanguageOffset);
    lines.add('${_codeOpeningFor(language)}</code>');
  }
  return lines;
}

class _Section {
  _Section(this.source, {required this.protected});

  String source;
  final bool protected;
  final key = GlobalKey();
  final editorKey = GlobalKey<quill.EditorState>();
  final gutterOrigin = GlobalKey();
  quill.QuillController? controller;
  FocusNode? focus;
  ScrollController? scroll;
  List<String> projected = const [];
  bool normalizingInput = false;

  void initialize() {
    if (protected) return;
    final ops = <Map<String, Object>>[];
    var inCode = false;
    final comments = DocumentComments(source);
    final literalRanges = [
      ...codeMarkup
          .allMatches(comments.maskedText)
          .where((match) => match.group(0)!.contains('\n')),
      ...comments.ranges,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final literals = literalRanges.iterator;
    var hasLiteral = literals.moveNext();
    var offset = 0;
    for (final line in source.split('\n')) {
      while (hasLiteral && literals.current.end <= offset) {
        hasLiteral = literals.moveNext();
      }
      final raw = hasLiteral && literals.current.start < offset + line.length;
      final isCode = !raw && documentCodeBlocks(line).isNotEmpty;
      if (raw) {
        // Preserve the original line boundaries and delimiters so selecting
        // across code and prose can use one editor.
        if (line.isNotEmpty)
          ops.add({
            'insert': line,
            'attributes': {'code': true},
          });
        ops.add({'insert': '\n'});
      } else {
        ops.addAll(_decodeLine(line, showCodeLanguage: isCode && !inCode));
      }
      inCode = isCode;
      offset += line.length + 1;
    }
    final document = quill.Document.fromJson(ops);
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

/// Keep the mode switch in view while the formatting tools scroll on narrow screens.
class DocumentEditorToolbar extends StatelessWidget {
  const DocumentEditorToolbar({
    super.key,
    required this.tools,
    required this.modeSwitch,
  });

  final List<Widget> tools;
  final Widget modeSwitch;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Row(
      children: [
        const SizedBox(width: _gutterWidth),
        Expanded(
          child: IconButtonTheme(
            data: IconButtonThemeData(style: _documentToolbarButtonStyle),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: tools),
            ),
          ),
        ),
        modeSwitch,
      ],
    ),
  );
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
    required this.onInsertFootnote,
    required this.onInsertTable,
    this.onInsertPhoto,
    this.onInsertDivider,
    this.onEditLines,
    this.sourceSelection,
    this.onCaretChanged,
    this.readOnly = false,
    required this.modeSwitch,
    required this.dirty,
    required this.diagnostics,
    required this.onSyntaxDiagnostic,
  });

  final String source;
  final List<ElementBinding> links;
  final void Function(int start, int end, String replacement) onPatch;
  final ValueChanged<String?> onLinkHover;
  final ValueChanged<int>? onInsertFootnote,
      onInsertTable,
      onInsertPhoto,
      onInsertDivider;
  final void Function(DocumentLineAction, TextSelection)? onEditLines;
  final TextSelection? sourceSelection;
  final ValueChanged<int>? onCaretChanged;
  final bool readOnly;
  final Widget modeSwitch;
  final bool dirty;
  final List<DocumentDiagnostic> diagnostics;
  final void Function(String? message, Offset position, {bool touch})
  onSyntaxDiagnostic;

  @override
  State<DocumentRichEditor> createState() => _DocumentRichEditorState();
}

class _DocumentRichEditorState extends State<DocumentRichEditor> {
  final _sections = <_Section>[];
  _Section? _active;
  (_Section, int)? _selectedBlock;

  @override
  void initState() {
    super.initState();
    final documentComments = DocumentComments(widget.source);
    final code = codeMarkup.allMatches(documentComments.maskedText).iterator;
    var hasCode = code.moveNext();
    final comments = documentComments.ranges.iterator;
    var hasComment = comments.moveNext();
    final group = <String>[];
    bool? protected;
    var offset = 0;
    void finish() {
      if (group.isEmpty) return;
      _sections.add(_Section(group.join('\n'), protected: protected!));
      group.clear();
    }

    final sourceLines = widget.source.split('\n');
    int? tableColumns;
    for (var row = 0; row < sourceLines.length; row++) {
      final line = sourceLines[row];
      final columns = tableCells(line)?.length;
      if (columns != tableColumns) tableColumns = null;
      if (columns != null &&
          row + 1 < sourceLines.length &&
          tableSeparator(sourceLines[row + 1], columns)) {
        tableColumns = columns;
      }
      final end = offset + line.length;
      while (hasComment && comments.current.end <= offset) {
        hasComment = comments.moveNext();
      }
      while (hasCode && code.current.end <= offset) {
        hasCode = code.moveNext();
      }
      final literal =
          (hasCode && code.current.start < end) ||
          (hasComment && comments.current.start < end);
      final isProtected =
          !literal &&
          ((documentListMarker.firstMatch(line)?.group(1)?.isNotEmpty ??
                  false) ||
              tableColumns != null ||
              (line.startsWith('|') && _sourceAlignment(line) == null) ||
              parseDocumentVisualBlock(line) != null ||
              documentFootnoteDefinition.hasMatch(line));
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
      section.controller?.addListener(() {
        _edited(section);
        if (_active == section)
          widget.onCaretChanged?.call(_insertionOffset(atCaret: true));
      });
      section.focus?.addListener(() {
        if (mounted &&
            section.focus!.hasFocus &&
            (_active != section || _selectedBlock != null)) {
          setState(() {
            _active = section;
            _selectedBlock = null;
          });
          widget.onCaretChanged?.call(_insertionOffset(atCaret: true));
        }
      });
    }
    _active = _sections.where((section) => !section.protected).firstOrNull;
    final selection = widget.sourceSelection;
    if (selection == null || !selection.isValid) return;
    var start = 0;
    for (final section in _sections) {
      final end = start + section.source.length;
      if (!section.protected &&
          selection.extentOffset >= start &&
          selection.extentOffset <= end) {
        final offsets = <int>[];
        final controller = section.controller!;
        _encodeLines(controller.document, contentOffsets: offsets);
        if (offsets.isEmpty) break;
        int editorOffset(int position) {
          final positionInSection = (position - start).clamp(
            0,
            section.source.length,
          );
          final prefix = section.source.substring(0, positionInSection);
          final row = '\n'
              .allMatches(prefix)
              .length
              .clamp(0, offsets.length - 1);
          final column = prefix.length - prefix.lastIndexOf('\n') - 1;
          final sourceLines = section.source.split('\n');
          final sourceLine = sourceLines[row.clamp(0, sourceLines.length - 1)];
          final sourceOffsets = <int>[];
          _decodeLine(sourceLine, sourceOffsets: sourceOffsets);
          final plain = controller.document.toPlainText();
          final lineEnd = plain.indexOf('\n', offsets[row]);
          final editorLine = plain.substring(
            offsets[row],
            lineEnd < 0 ? plain.length : lineEnd,
          );
          final editorColumn = editorLine == sourceLine
              ? column
              : sourceOffsets.where((offset) => offset < column).length;
          final last = row + 1 < offsets.length
              ? offsets[row + 1] - 1
              : controller.document.length - 1;
          return (offsets[row] + editorColumn).clamp(offsets[row], last);
        }

        _active = section;
        controller.updateSelection(
          TextSelection(
            baseOffset: editorOffset(selection.baseOffset),
            extentOffset: editorOffset(selection.extentOffset),
          ),
          quill.ChangeSource.local,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) section.focus!.requestFocus();
        });
        break;
      }
      start = end + 1;
    }
  }

  bool _appendSectionOnEdit = false;

  void _recognizeListPrefix(_Section section) {
    final controller = section.controller!;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final caret = selection.extentOffset;
    final plain = controller.document.toPlainText();
    if (caret <= 0 || caret >= plain.length) return;
    final start = plain.lastIndexOf('\n', caret - 1) + 1;
    final prefix = plain.substring(start, caret);
    final type = switch (prefix) {
      '1. ' => 'ordered',
      '- ' => 'bullet',
      _ => null,
    };
    if (type == null) return;
    final style = controller.getSelectionStyle().attributes;
    if (style.containsKey('list') ||
        style.containsKey('code-block') ||
        style.containsKey('code') ||
        style.containsKey('header'))
      return;
    if (caretInsideCode(plain, caret) ||
        DocumentComments(plain).ranges
            .any((range) => range.start <= start && range.end >= caret))
      return;
    final lineEnd = plain.indexOf('\n', caret);
    section.normalizingInput = true;
    try {
      controller.compose(
        Delta()
          ..retain(start)
          ..delete(prefix.length)
          ..retain(lineEnd - caret)
          ..retain(1, {'list': type}),
        selection,
        quill.ChangeSource.local,
      );
    } finally {
      section.normalizingInput = false;
    }
  }

  void _edited(_Section section) {
    if (section.normalizingInput) return;
    _recognizeListPrefix(section);
    final controller = section.controller!;
    final missing = <int>[];
    var next = _encodeLines(
      controller.document,
      missingLanguageOffsets: missing,
    );
    if (missing.isNotEmpty) {
      section.normalizingInput = true;
      try {
        final delta = Delta();
        var previous = 0;
        for (final offset in missing) {
          delta
            ..retain(offset - previous)
            ..insert(_emptyCodeLanguageLine)
            ..insert('\n', _codeLineAttributes);
          previous = offset;
        }
        controller.compose(
          delta,
          controller.selection,
          quill.ChangeSource.local,
        );
      } finally {
        section.normalizingInput = false;
      }
      next = _encodeLines(controller.document);
    }
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
      for (var i = start; i < newEnd; i++) next[i],
      ...sourceLines.skip(oldEnd),
    ].join('\n');
    section.projected = next;
    _updateSection(section, updated);
  }

  void _updateSection(
    _Section section,
    String updated, {
    int? patchStart,
    int? patchEnd,
    String? replacement,
  }) {
    var offset = 0;
    for (final other in _sections) {
      if (identical(other, section)) break;
      offset += other.source.length + 1;
    }
    final previousLength = section.source.length;
    section.source = updated;
    if (mounted) setState(() {});
    if (_appendSectionOnEdit && identical(section, _sections.last)) {
      _appendSectionOnEdit = false;
      widget.onPatch(offset - 1, offset - 1, '\n$updated');
    } else {
      widget.onPatch(
        offset + (patchStart ?? 0),
        offset + (patchEnd ?? previousLength),
        replacement ?? updated,
      );
    }
  }

  void _editProtectedCode(
    _Section section,
    int start,
    String previous,
    String value,
  ) {
    final opening = documentCodeOpening.matchAsPrefix(previous)!;
    final newline = value.indexOf('\n');
    final firstLine = newline == -1 ? value : value.substring(0, newline);
    final hasLanguageLine = firstLine.startsWith(_codeLanguagePrefix);
    final language = hasLanguageLine ? _readLanguageLine(firstLine) : '';
    final code = hasLanguageLine
        ? (newline < 0 ? '' : value.substring(newline + 1))
        : value;
    final leadingBreak = previous.startsWith('\n', opening.end) ? '\n' : '';
    final trailingBreak =
        previous.endsWith('\n</code>') &&
            previous.length - 7 > opening.end + leadingBreak.length
        ? '\n'
        : '';
    final updated =
        '${_codeOpeningFor(language)}$leadingBreak$code$trailingBreak</code>';
    if (updated == previous) return;
    _updateSection(
      section,
      section.source.replaceRange(start, start + previous.length, updated),
      patchStart: start,
      patchEnd: start + previous.length,
      replacement: updated,
    );
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

  void _editVisualBlock(
    _Section section,
    int start,
    String Function(DocumentVisualBlock) edit,
  ) {
    final newline = section.source.indexOf('\n', start);
    final end = newline < 0 ? section.source.length : newline;
    final current = section.source.substring(start, end);
    final block = parseDocumentVisualBlock(current);
    if (block == null) return;
    final value = edit(block);
    if (value == current) return;
    if (value.isEmpty) _selectedBlock = null;
    _updateSection(
      section,
      section.source.replaceRange(start, end, value),
      patchStart: start,
      patchEnd: end,
      replacement: value,
    );
  }

  void _alignBlock(
    _Section section,
    int start,
    DocumentBlockAlignment alignment,
  ) => _editVisualBlock(
    section,
    start,
    (block) => alignDocumentVisualBlock(block.markup, alignment),
  );

  Widget _alignmentButton(
    String label,
    IconData icon,
    quill.Attribute attribute,
  ) => IconButton(
    tooltip: label,
    icon: Icon(icon),
    onPressed: widget.readOnly
        ? null
        : () {
            final selected = _selectedBlock;
            if (selected != null) {
              final alignment = switch (attribute.value) {
                'center' => DocumentBlockAlignment.center,
                'right' => DocumentBlockAlignment.right,
                _ => DocumentBlockAlignment.left,
              };
              _alignBlock(selected.$1, selected.$2, alignment);
              return;
            }
            final section = _active;
            if (section == null) return;
            section.controller!.formatSelection(attribute);
            section.focus!.requestFocus();
          },
  );

  void _editLines(_Section section, DocumentLineAction action) {
    final controller = section.controller!;
    final selection = controller.selection;
    if (!selection.isValid) return;
    final offsets = <int>[];
    _encodeLines(controller.document, contentOffsets: offsets);
    var sectionStart = 0;
    for (final other in _sections) {
      if (identical(other, section)) break;
      sectionStart += other.source.length + 1;
    }
    final lines = section.source.split('\n');
    int sourceOffset(int position) {
      final row = offsets
          .lastIndexWhere((offset) => offset <= position)
          .clamp(0, lines.length - 1);
      final start =
          sectionStart +
          lines
              .take(row)
              .fold<int>(0, (length, line) => length + line.length + 1);
      if (offsets.isEmpty) return start;
      final column = position - offsets[row];
      return start + column.clamp(0, lines[row].length);
    }

    widget.onEditLines?.call(
      action,
      TextSelection(
        baseOffset: sourceOffset(selection.baseOffset),
        extentOffset: sourceOffset(selection.extentOffset),
      ),
    );
  }

  int _insertionOffset({bool atCaret = false}) {
    final selected = _selectedBlock;
    if (!atCaret && selected != null) {
      var offset = 0;
      for (final section in _sections) {
        if (identical(section, selected.$1)) return offset + selected.$2;
        offset += section.source.length + 1;
      }
    }
    final section = _active;
    final controller = section?.controller;
    if (section == null || controller == null) return widget.source.length;
    final offsets = <int>[];
    _encodeLines(controller.document, contentOffsets: offsets);
    final caret = controller.selection.extentOffset;
    var row = offsets.lastIndexWhere((offset) => offset <= caret);
    if (row < 0) row = 0;
    final sourceLines = section.source.split('\n');
    var offset = 0;
    for (final other in _sections) {
      if (identical(other, section)) break;
      offset += other.source.length + 1;
    }
    for (var i = 0; i < row && i < sourceLines.length; i++) {
      offset += sourceLines[i].length + 1;
    }
    if (row >= sourceLines.length) return offset - 1;
    final line = sourceLines[row];
    if (atCaret && row < offsets.length) {
      final plain = controller.document.toPlainText();
      final rowStart = offsets[row];
      final newline = plain.indexOf('\n', rowStart);
      final editorLine = plain.substring(
        rowStart,
        newline < 0 ? plain.length : newline,
      );
      final column = (caret - rowStart).clamp(0, editorLine.length);
      if (line == editorLine) return offset + column;
      final sourceOffsets = <int>[];
      _decodeLine(line, sourceOffsets: sourceOffsets);
      if (sourceOffsets.isNotEmpty) {
        if (column == 0) return offset + sourceOffsets.first;
        final previous =
            sourceOffsets[(column - 1).clamp(0, sourceOffsets.length - 1)];
        final reference = editorLine[column - 1] == '\uFFFC'
            ? documentFootnoteReference.matchAsPrefix(line, previous)
            : null;
        return offset + (reference?.end ?? previous + 1);
      }
    }
    final heading = projectHeading.firstMatch(line);
    if (_sourceAlignment(line) != null) {
      return offset + line.substring(0, line.length - 1).trimRight().length;
    }
    return offset + line.length - (heading?.group(1)?.length ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final inputBorder = Theme.of(context).inputDecorationTheme.enabledBorder;
    final inputRadius = inputBorder is OutlineInputBorder
        ? inputBorder.borderRadius
        : const OutlineInputBorder().borderRadius;
    final numbering = DocumentHeadingNumbers();
    final headings = <({String title, _Section section, int offset})>[];
    for (final section in _sections) {
      final offsets = <int>[];
      final lines = section.protected
          ? DocumentComments(section.source).visibleText
                .replaceAllMapped(
                  codeMarkup,
                  (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
                )
                .split('\n')
          : _encodeLines(section.controller!.document, contentOffsets: offsets);
      for (var i = 0; i < lines.length; i++) {
        final match = projectHeading.firstMatch(lines[i]);
        if (match != null) {
          final prefix = numbering.next(match.group(1)!.length);
          if (prefix.isNotEmpty) {
            headings.add((
              title: '$prefix${match.group(2)!.trim()}',
              section: section,
              offset: section.protected ? 0 : offsets[i],
            ));
          }
        }
      }
    }
    final source = DocumentComments(
      _sections.map((section) => section.source).join('\n'),
    ).visibleText.replaceAll(codeMarkup, '');
    final bodyLines = <String>[];
    final definitions = <String>{};
    for (final line in source.split('\n')) {
      final definition = documentFootnoteDefinition.firstMatch(line);
      if (definition == null) {
        bodyLines.add(line);
      } else {
        definitions.add(definition.group(1)!);
      }
    }
    final notes = <String, int>{};
    for (final reference in documentFootnoteReference.allMatches(
      bodyLines.join('\n'),
    )) {
      final id = reference.group(1)!;
      if (definitions.contains(id))
        notes.putIfAbsent(id, () => notes.length + 1);
    }
    final sectionWidgets = <Widget>[];
    var sectionStart = 0;
    var firstLine = 1;
    for (final section in _sections) {
      final sectionEnd = sectionStart + section.source.length;
      final lineCount = '\n'.allMatches(section.source).length + 1;
      final diagnoses = {
        for (final issue in widget.diagnostics)
          if (issue.line >= firstLine - 1 &&
              issue.line < firstLine - 1 + lineCount)
            issue.line - firstLine + 1: issue,
      };
      sectionWidgets.add(
        section.protected
            ? _ProtectedDocumentSource(
                key: section.key,
                firstLine: firstLine,
                diagnostics: diagnoses,
                source: section.source,
                readOnly: widget.readOnly,
                selectedBlock: identical(_selectedBlock?.$1, section)
                    ? _selectedBlock?.$2
                    : null,
                onSelectBlock: (start) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(
                    () => _selectedBlock = (_selectedBlock == (section, start))
                        ? null
                        : (section, start),
                  );
                },
                onAlignBlock: (start, alignment) =>
                    _alignBlock(section, start, alignment),
                onResizeBlock: (start, width) => _editVisualBlock(
                  section,
                  start,
                  (block) => resizeDocumentVisualBlock(block, width),
                ),
                onDeleteBlock: (start) =>
                    _editVisualBlock(section, start, (_) => ''),
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
                onCodeChanged: (start, raw, value) =>
                    _editProtectedCode(section, start, raw, value),
              )
            : _QuillEditorBlock(
                section: section,
                readOnly: widget.readOnly,
                noteNumbers: notes,
                onEditLines: (action) => _editLines(section, action),
                firstLine: firstLine,
                diagnostics: diagnoses,
                onSyntaxDiagnostic: widget.onSyntaxDiagnostic,
                key: section.key,
              ),
      );
      firstLine += lineCount;
      sectionStart = sectionEnd + 1;
    }
    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DocumentEditorToolbar(
            key: const ValueKey('document-editor-toolbar'),
            modeSwitch: widget.modeSwitch,
            tools: [
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
              const VerticalDivider(width: 12, indent: 8, endIndent: 8),
              _alignmentButton(
                '왼쪽 정렬',
                Icons.format_align_left,
                quill.Attribute.leftAlignment,
              ),
              _alignmentButton(
                '가운데 정렬',
                Icons.format_align_center,
                quill.Attribute.centerAlignment,
              ),
              _alignmentButton(
                '오른쪽 정렬',
                Icons.format_align_right,
                quill.Attribute.rightAlignment,
              ),
              const VerticalDivider(width: 12, indent: 8, endIndent: 8),
              PopupMenuButton<int>(
                tooltip: '제목 단계',
                style: _documentToolbarButtonStyle,
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.title),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 0, child: Text('본문')),
                  const PopupMenuItem(value: 1, child: Text('문서 제목')),
                  for (var level = 2; level <= 5; level++)
                    PopupMenuItem(value: level, child: Text('제목 ${level - 1}')),
                ],
                enabled: !widget.readOnly,
                onSelected: (level) {
                  final section = _active;
                  if (section == null) return;
                  section.controller!.formatSelection(
                    quill.HeaderAttribute(level: level == 0 ? null : level),
                  );
                  section.focus!.requestFocus();
                },
              ),
              _formatButton(
                '번호 목록',
                Icons.format_list_numbered,
                quill.Attribute.ol,
              ),
              PopupMenuButton<bool>(
                tooltip: '글머리표',
                enabled: !widget.readOnly,
                style: _documentToolbarButtonStyle,
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.format_list_bulleted),
                constraints: const BoxConstraints.tightFor(width: 64),
                itemBuilder: (_) => [
                  for (final (dash, symbol) in [(false, '•'), (true, '-')])
                    PopupMenuItem(
                      value: dash,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Center(child: Text(symbol)),
                    ),
                ],
                onSelected: (dash) =>
                    _toggle(dash ? _dashBullet : quill.Attribute.ul),
              ),
              const VerticalDivider(width: 12, indent: 8, endIndent: 8),
              IconButton(
                tooltip: '구분선 삽입',
                icon: const Icon(Icons.horizontal_rule),
                onPressed: widget.onInsertDivider == null
                    ? null
                    : () => widget.onInsertDivider!(_insertionOffset()),
              ),
              IconButton(
                tooltip: '표 삽입',
                icon: const Icon(Icons.table_chart_outlined),
                onPressed: widget.onInsertTable == null
                    ? null
                    : () => widget.onInsertTable!(_insertionOffset()),
              ),
              IconButton(
                tooltip: '사진 삽입',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: widget.onInsertPhoto == null
                    ? null
                    : () => widget.onInsertPhoto!(_insertionOffset()),
              ),
              IconButton(
                tooltip: '각주',
                icon: const Text('≡¹'),
                onPressed: widget.onInsertFootnote == null
                    ? null
                    : () => widget.onInsertFootnote!(
                        _insertionOffset(atCaret: true),
                      ),
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
                    final controller = entry.section.controller;
                    if (controller == null) return;
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
              _formatButton('코드 블록', Icons.code, quill.Attribute.codeBlock),
            ],
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  left: _gutterWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: inputRadius,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.only(
                    top: 12,
                    bottom: widget.dirty ? 36 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: sectionWidgets,
                  ),
                ),
                if (widget.dirty)
                  const Positioned(
                    left: _gutterWidth + 12,
                    right: 12,
                    bottom: 8,
                    child: IgnorePointer(
                      child: Text(
                        '아직 저장되지 않았습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ),
              ],
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
    onPressed: widget.readOnly ? null : () => _toggle(attribute),
  );
}

final _documentToolbarButtonStyle = IconButton.styleFrom(
  minimumSize: const Size.square(32),
  maximumSize: const Size.square(32),
  padding: EdgeInsets.zero,
  iconSize: 18,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

const _gutterWidth = 42.0;

String _codeOpeningFor(String value) {
  final language = value.trim();
  return language.isEmpty ? '<code>' : '<code lang="$language">';
}

TextStyle _lineNumberStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

class _FootnoteEmbedBuilder extends quill.EmbedBuilder {
  const _FootnoteEmbedBuilder(this.numbers);

  final Map<String, int> numbers;

  @override
  String get key => _footnoteEmbed;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) =>
      WidgetSpan(alignment: PlaceholderAlignment.top, child: widget);

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final number = numbers[embedContext.node.value.data];
    final style = embedContext.textStyle;
    return Text(
      number == null ? '[?]' : '[$number]',
      style: style.copyWith(
        color: Colors.orange.shade800,
        fontSize: (style.fontSize ?? 14) * .72,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class _QuillEditorBlock extends StatelessWidget {
  const _QuillEditorBlock({
    super.key,
    required this.section,
    required this.onEditLines,
    required this.noteNumbers,
    required this.readOnly,
    required this.firstLine,
    required this.diagnostics,
    required this.onSyntaxDiagnostic,
  });
  final _Section section;
  final ValueChanged<DocumentLineAction> onEditLines;
  final Map<String, int> noteNumbers;
  final bool readOnly;
  final int firstLine;
  final Map<int, DocumentDiagnostic> diagnostics;
  final void Function(String? message, Offset position, {bool touch})
  onSyntaxDiagnostic;

  @override
  Widget build(BuildContext context) {
    final controller = section.controller!..readOnly = readOnly;
    final contentOffsets = <int>[];
    _encodeLines(controller.document, contentOffsets: contentOffsets);
    final issuesByOffset = <int, DocumentDiagnostic>{
      for (var i = 0; i < contentOffsets.length; i++)
        if (diagnostics[i] case final issue?) contentOffsets[i]: issue,
    };
    return Stack(
      key: section.gutterOrigin,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: _gutterWidth),
          child: CallbackShortcuts(
            bindings: {
              for (final entry in documentLineShortcuts.entries)
                entry.key: () => onEditLines(entry.value),
            },
            child: quill.QuillEditor.basic(
              controller: controller,
              focusNode: section.focus!,
              scrollController: section.scroll!,
              config: quill.QuillEditorConfig(
                editorKey: section.editorKey,
                embedBuilders: [_FootnoteEmbedBuilder(noteNumbers)],
                customLeadingBlockBuilder: (_, leading) {
                  if (leading.attribute != _dashBullet) return null;
                  return SizedBox(
                    width: 24,
                    child: Text('-', style: DefaultTextStyle.of(context).style),
                  );
                },
                textSpanBuilder:
                    (context, node, nodeOffset, text, style, recognizer) {
                      final issue = issuesByOffset[node.parent?.documentOffset];
                      if (issue == null) {
                        return quill.defaultSpanBuilder(
                          context,
                          node,
                          nodeOffset,
                          text,
                          style,
                          recognizer,
                        );
                      }
                      return TextSpan(
                        text: text,
                        style: (style ?? const TextStyle()).merge(
                          documentDiagnosticStyle(context),
                        ),
                        recognizer: recognizer,
                        onEnter: (event) =>
                            onSyntaxDiagnostic(issue.message, event.position),
                        onExit: (event) =>
                            onSyntaxDiagnostic(null, event.position),
                      );
                    },
                onTapUp: (details, positionAt) {
                  if (details.kind != PointerDeviceKind.touch ||
                      issuesByOffset.isEmpty)
                    return false;
                  final plain = controller.document.toPlainText();
                  final offset = positionAt(details.globalPosition).offset
                      .clamp(0, plain.length);
                  final start = offset == 0
                      ? 0
                      : plain.lastIndexOf('\n', offset - 1) + 1;
                  final issue = issuesByOffset[start];
                  if (issue != null)
                    onSyntaxDiagnostic(
                      issue.message,
                      details.globalPosition,
                      touch: true,
                    );
                  return false;
                },
                scrollable: false,
                showCodeBlockLineNumbers: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _gutterWidth,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _QuillLineNumbers(
                editorKey: section.editorKey,
                originKey: section.gutterOrigin,
                offsets: contentOffsets,
                firstLine: firstLine,
                style: _lineNumberStyle(context),
                scaler: MediaQuery.textScalerOf(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuillLineNumbers extends CustomPainter {
  _QuillLineNumbers({
    required this.editorKey,
    required this.originKey,
    required this.offsets,
    required this.firstLine,
    required this.style,
    required this.scaler,
  });

  final GlobalKey<quill.EditorState> editorKey;
  final GlobalKey originKey;
  final List<int> offsets;
  final int firstLine;
  final TextStyle style;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final render = editorKey.currentState?.renderEditor;
    if (render == null || !render.hasSize || size.isEmpty) return;
    // The editor padding is also the render object's origin inside the row.
    final origin = originKey.currentContext?.findRenderObject();
    if (origin is! RenderBox) return;
    final top = render.localToGlobal(Offset.zero, ancestor: origin).dy;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final label = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    var line = firstLine;
    for (final start in offsets) {
      final caret = render.getLocalRectForCaret(TextPosition(offset: start));
      label.text = TextSpan(text: '${line++}', style: style);
      label.layout();
      label.paint(
        canvas,
        Offset(
          size.width - label.width - 8,
          top + caret.center.dy - label.height / 2,
        ),
      );
    }
    label.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QuillLineNumbers oldDelegate) => true;
}

class _ProtectedDocumentSource extends StatelessWidget {
  const _ProtectedDocumentSource({
    super.key,
    required this.firstLine,
    required this.diagnostics,
    required this.source,
    required this.readOnly,
    required this.selectedBlock,
    required this.onSelectBlock,
    required this.onAlignBlock,
    required this.onResizeBlock,
    required this.onDeleteBlock,
    required this.links,
    required this.onLinkHover,
    required this.onCodeChanged,
  });
  final int firstLine;
  final Map<int, DocumentDiagnostic> diagnostics;
  final String source;
  final bool readOnly;
  final int? selectedBlock;
  final ValueChanged<int> onSelectBlock;
  final void Function(int, DocumentBlockAlignment) onAlignBlock;
  final void Function(int, int) onResizeBlock;
  final ValueChanged<int> onDeleteBlock;
  final List<ElementBinding> links;
  final ValueChanged<String?> onLinkHover;
  final void Function(int start, String raw, String value) onCodeChanged;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    Widget textSegment(int start, int end, DocumentDiagnostic? issue) {
      final segmentLinks = [
        for (final link in links)
          if (link.start < end && link.end > start)
            ElementBinding(
              link.id,
              link.start.clamp(start, end) - start,
              link.end.clamp(start, end) - start,
            ),
      ];
      final text = source.substring(start, end);
      final block = parseDocumentVisualBlock(text);
      if (block != null) {
        return _EditableVisualBlock(
          key: ValueKey((start, block.photoId)),
          block: block,
          selected: selectedBlock == start,
          readOnly: readOnly,
          onSelect: () => onSelectBlock(start),
          onAlign: (alignment) => onAlignBlock(start, alignment),
          onResize: (width) => onResizeBlock(start, width),
          onDelete: () => onDeleteBlock(start),
        );
      }
      final style = issue == null ? null : documentDiagnosticStyle(context);
      final content = segmentLinks.isEmpty
          ? SelectableText(text, style: style)
          : SelectionArea(
              child: CanvasLinkText(
                text: text,
                links: segmentLinks,
                enabled: true,
                editingDocument: true,
                onLinkHover: onLinkHover,
                style: style,
              ),
            );
      return issue == null
          ? content
          : Tooltip(
              message: issue.message,
              triggerMode: TooltipTriggerMode.tap,
              child: content,
            );
    }

    int line = firstLine;
    Widget numbered(int number, Widget child) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: _lineNumberStyle(context),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: child,
          ),
        ),
      ],
    );
    void addLines(int start, int end) {
      while (start < end) {
        final newline = source.indexOf('\n', start);
        final lineEnd = newline >= 0 && newline < end ? newline : end;
        if (documentFootnoteDefinition.hasMatch(
          source.substring(start, lineEnd),
        )) {
          line++;
          start = lineEnd + 1;
          continue;
        }
        children.add(
          numbered(
            line++,
            lineEnd == start
                ? const Text(' ')
                : textSegment(
                    start,
                    lineEnd,
                    diagnostics[line - firstLine - 1],
                  ),
          ),
        );
        start = lineEnd + 1;
      }
    }

    var offset = 0;
    var blockIndex = 0;
    for (final block in documentCodeBlocks(
      DocumentComments(source).maskedText,
    )) {
      addLines(offset, block.start);
      final raw = source.substring(block.start, block.end);
      final code = documentCodeBody(raw);
      final language = documentCodeLanguage(raw);
      final opening = documentCodeOpening.matchAsPrefix(raw)!;
      final codeKey = ValueKey(blockIndex++);
      final firstCodeLine = line + (raw.startsWith('\n', opening.end) ? 1 : 0);
      final codeLineCount = '\n'.allMatches(code).length + 1;
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _gutterWidth,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 27),
                child: Text(
                  List.generate(
                    codeLineCount,
                    (index) => firstCodeLine + index,
                  ).join('\n'),
                  textAlign: TextAlign.right,
                  style: documentCodeStyle(context).copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: DecoratedBox(
                  decoration: documentCodeDecoration(context),
                  child: TextFormField(
                    key: codeKey,
                    readOnly: readOnly,
                    initialValue: '${_languageLine(language)}\n$code',
                    minLines: 2,
                    maxLines: null,
                    style: documentCodeStyle(context),
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) =>
                        onCodeChanged(block.start, raw, value),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      line += '\n'.allMatches(raw).length + 1;
      offset = block.end;
      if (offset < source.length && source[offset] == '\n') offset++;
    }
    addLines(offset, source.length);
    if (source.endsWith('\n')) children.add(numbered(line, const Text(' ')));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _EditableVisualBlock extends StatefulWidget {
  const _EditableVisualBlock({
    super.key,
    required this.block,
    required this.selected,
    required this.readOnly,
    required this.onSelect,
    required this.onAlign,
    required this.onResize,
    required this.onDelete,
  });

  final DocumentVisualBlock block;
  final bool selected, readOnly;
  final VoidCallback onSelect, onDelete;
  final ValueChanged<DocumentBlockAlignment> onAlign;
  final ValueChanged<int> onResize;

  @override
  State<_EditableVisualBlock> createState() => _EditableVisualBlockState();
}

class _EditableVisualBlockState extends State<_EditableVisualBlock> {
  final _portal = OverlayPortalController();
  final _focus = FocusNode();
  bool _hovered = false;

  void _enter() {
    if (!_hovered) setState(() => _hovered = true);
    if (!_portal.isShowing) _portal.show();
  }

  void _leave() {
    _hovered = false;
    // A pointer moving onto the toolbar can enter it in the same dispatch.
    scheduleMicrotask(() {
      if (!mounted || _hovered) return;
      setState(() {});
      if (!widget.selected) _portal.hide();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Widget _toolbar(BuildContext context, OverlayChildLayoutInfo layout) {
    if (widget.readOnly || (!_hovered && !widget.selected))
      return const SizedBox.shrink();
    final label = widget.block.photoId == null ? '구분선' : '사진';
    final width = widget.block.widthPercent;
    const toolbarWidth = 128.0;
    const toolbarHeight = 64.0;
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final size = layout.overlaySize;
    if (!anchor.overlaps(Offset.zero & size)) return const SizedBox.shrink();
    final above = anchor.bottom + toolbarHeight > size.height;
    final top = (above ? anchor.top - toolbarHeight : anchor.bottom)
        .clamp(0.0, (size.height - toolbarHeight).clamp(0.0, double.infinity));
    return Positioned(
      left: (anchor.center.dx - toolbarWidth / 2).clamp(
        0.0,
        (size.width - toolbarWidth).clamp(0.0, double.infinity),
      ),
      top: top,
      width: toolbarWidth,
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _leave(),
        child: Material(
          elevation: 4,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          child: IconButtonTheme(
            data: IconButtonThemeData(style: _documentToolbarButtonStyle),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (alignment, title, icon) in [
                      (
                        DocumentBlockAlignment.left,
                        '왼쪽 정렬',
                        Icons.format_align_left,
                      ),
                      (
                        DocumentBlockAlignment.center,
                        '가운데 정렬',
                        Icons.format_align_center,
                      ),
                      (
                        DocumentBlockAlignment.right,
                        '오른쪽 정렬',
                        Icons.format_align_right,
                      ),
                    ])
                      IconButton(
                        tooltip: '$label $title',
                        isSelected: widget.block.alignment == alignment,
                        icon: Icon(icon),
                        onPressed: () => widget.onAlign(alignment),
                      ),
                    IconButton(
                      tooltip: '$label 삭제',
                      icon: const Icon(Icons.close),
                      onPressed: widget.onDelete,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '$label 너비 줄이기',
                      icon: const Icon(Icons.remove),
                      onPressed: width <= 10
                          ? null
                          : () => widget.onResize(width - 10),
                    ),
                    Text(
                      '$width%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    IconButton(
                      tooltip: '$label 너비 늘리기',
                      icon: const Icon(Icons.add),
                      onPressed: width >= 100
                          ? null
                          : () => widget.onResize(width + 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = DocumentVisualBlockView(widget.block);
    if (widget.readOnly) return view;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _toolbar,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (_, event) {
          if (widget.selected &&
              event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.backspace ||
                  event.logicalKey == LogicalKeyboardKey.delete)) {
            widget.onDelete();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _leave(),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              canRequestFocus: false,
              onTap: () {
                widget.onSelect();
                _focus.requestFocus();
                if (!_portal.isShowing) _portal.show();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: widget.selected
                      ? Border.all(color: Theme.of(context).colorScheme.primary)
                      : null,
                ),
                child: view,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

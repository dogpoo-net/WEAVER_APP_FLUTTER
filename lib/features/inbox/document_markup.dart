import 'document_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'element_binding.dart';
import 'label_links.dart';

export 'document_syntax.dart' show documentTitle;
import 'document_syntax.dart';

class DocumentMarkup extends StatefulWidget {
  const DocumentMarkup({super.key, required this.text, this.links = const [], this.style, this.formatting = true});
  final String text;
  final List<ElementBinding> links;
  final TextStyle? style;
  final bool formatting;
  @override
  State<DocumentMarkup> createState() => _DocumentMarkupState();
}
class _DocumentMarkupState extends State<DocumentMarkup> {
  Map<int, ElementBinding> _linksAt = {};
  bool _inCode = false;
  final _footnotes = <String, String>{};
  final _numbers = <String, int>{};
  final _noteKeys = <String, GlobalKey>{};

  void _jump(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240));
    }
  }

  Widget _footnoteMarker(String id, TextStyle style) {
    final number = '[${_numbers[id]}]';
    final key = _noteKeys.putIfAbsent(id, GlobalKey.new);
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final marker = InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () async {
        if (!mobile) {
          _jump(key);
          return;
        }
        final jump = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Align(alignment: Alignment.centerLeft, child: TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(number),
            )),
            content: SingleChildScrollView(child: Text(_footnotes[id] ?? '')),
          ),
        );
        if (mounted && jump == true) _jump(key);
      },
      child: Text(number, style: style.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      )),
    );
    return mobile ? marker : Tooltip(message: _footnotes[id]!, child: marker);
  }

  String? _hovered;
  final _recognizers = <String, TapGestureRecognizer>{};
  List<InlineSpan> _inline(String text, int base, TextStyle style, {bool tableCell = false}) {
    final result = <InlineSpan>[];
    var i = 0;
    final plain = StringBuffer();
    void flush() { if (plain.isNotEmpty) { result.add(TextSpan(text: plain.toString(), style: style)); plain.clear(); } }
    while (i < text.length) {
      if (tableCell && text.startsWith('<br>', i)) { plain.write('\n'); i += 4; continue; }
      if (tableCell && text[i] == '\\' && i + 1 < text.length && ['|', '\\'].contains(text[i + 1])) { plain.write(text[i + 1]); i += 2; continue; }
      if (widget.formatting && (_inCode || text.startsWith('<code>', i))) {
        flush();
        if (!_inCode) i += 6;
        final close = text.indexOf('</code>', i);
        final end = close < 0 ? text.length : close;
        result.add(TextSpan(text: text.substring(i, end), style: style.copyWith(
          fontFamily: 'monospace', fontWeight: FontWeight.normal, fontStyle: FontStyle.normal,
          decoration: TextDecoration.none, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest)));
        _inCode = close < 0;
        i = close < 0 ? end : close + 7;
        continue;
      }
      final candidate = _linksAt[base + i];
      final link = candidate != null && candidate.end <= base + text.length ? candidate : null;
      if (link != null) {
        flush();
        final recognizer = _recognizers.putIfAbsent('${link.start}:${link.id}', () => TapGestureRecognizer())..onTap = () => openInlineLink(context, link.id);
        result.add(TextSpan(text: text.substring(i, link.end - base), style: style.merge(inlineLinkStyle(context, link.id, hovered: _hovered == link.id)), recognizer: recognizer, mouseCursor: SystemMouseCursors.click, onEnter: (_) => setState(() => _hovered = link.id), onExit: (_) => setState(() => _hovered = null)));
        i = link.end - base; continue;
      }
      if (widget.formatting && text[i] == '[') {
        final reference = documentFootnoteReference.matchAsPrefix(text, i);
        final id = reference?.group(1);
        if (id != null && _footnotes.containsKey(id)) {
          flush();
          _numbers.putIfAbsent(id, () => _numbers.length + 1);
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _footnoteMarker(id, style),
          ));
          i = reference!.end;
          continue;
        }
      }
      var matched = false;
      if (widget.formatting) {
        for (final marker in ['**', '//', '__', '--']) {
          if (!text.startsWith(marker, i)) continue;
          final end = text.indexOf(marker, i + 2);
          if (end < 0 || end == i + 2 || (marker == '//' && i > 0 && text[i - 1] == ':')) continue;
          final next = switch (marker) {
            '**' => style.copyWith(fontWeight: FontWeight.bold),
            '//' => style.copyWith(fontStyle: FontStyle.italic),
            '__' => style.copyWith(decoration: TextDecoration.combine([if (style.decoration != null) style.decoration!, TextDecoration.underline])),
            _ => style.copyWith(decoration: TextDecoration.combine([if (style.decoration != null) style.decoration!, TextDecoration.lineThrough])),
          };
          flush();
          result.addAll(_inline(text.substring(i + 2, end), base + i + 2, next, tableCell: tableCell));
          i = end + 2; matched = true; break;
        }
      }
      if (!matched) { plain.write(text[i]); i++; }
    }
    flush();
    return result;
  }
  @override
  void dispose() { for (final r in _recognizers.values) { r.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    _inCode = false;
    _linksAt = {for (final b in widget.links) b.start: b};
    final keys = {for (final b in widget.links) '${b.start}:${b.id}'};
    for (final key in _recognizers.keys.where((key) => !keys.contains(key)).toList()) { _recognizers.remove(key)!.dispose(); }
    final baseStyle = widget.style ?? Theme.of(context).textTheme.bodyLarge!;
    final lines = <Widget>[];
    var offset = 0;
    final sourceLines = widget.text.split('\n');
    _footnotes.clear();
    _numbers.clear();
    final headings = <({String title, GlobalKey key})>[];
    if (widget.formatting) {
      final prose = widget.text.replaceAll(codeMarkup, '\n');
      final body = StringBuffer();
      for (final line in prose.split('\n')) {
        final definition = documentFootnoteDefinition.firstMatch(line);
        if (definition != null) {
          _footnotes.putIfAbsent(definition.group(1)!, () => definition.group(2)!);
        } else if (!documentEditorComment.hasMatch(line)) {
          body.writeln(line);
        }
      }
      for (final reference in documentFootnoteReference.allMatches(body.toString())) {
        final id = reference.group(1)!;
        if (_footnotes.containsKey(id)) {
          _numbers.putIfAbsent(id, () => _numbers.length + 1);
          _noteKeys.putIfAbsent(id, GlobalKey.new);
        }
      }
      _noteKeys.removeWhere((id, _) => !_footnotes.containsKey(id));
    }
    for (var lineIndex = 0; lineIndex < sourceLines.length; lineIndex++) {
      final line = sourceLines[lineIndex];
      if (widget.formatting && !_inCode &&
          (documentEditorComment.hasMatch(line) || documentFootnoteDefinition.hasMatch(line))) {
        offset += line.length + 1;
        continue;
      }
      GlobalKey? headingKey;
      final header = tableCells(line);
      if (widget.formatting && !_inCode && header != null && lineIndex + 1 < sourceLines.length && tableSeparator(sourceLines[lineIndex + 1], header.length)) {
        final tableRows = <({List<TableCellSource> cells, int offset})>[(cells: header, offset: offset)];
        offset += line.length + 1 + sourceLines[++lineIndex].length + 1;
        while (lineIndex + 1 < sourceLines.length) {
          final cells = tableCells(sourceLines[lineIndex + 1]);
          if (cells == null || cells.length != header.length) break;
          tableRows.add((cells: cells, offset: offset)); offset += sourceLines[++lineIndex].length + 1;
        }
        lines.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: LayoutBuilder(builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth / header.length).clamp(120.0, 300.0);
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Table(defaultColumnWidth: FixedColumnWidth(cellWidth),
            border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant), children: [
              for (var row = 0; row < tableRows.length; row++) TableRow(decoration: row == 0 ? BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest) : null,
                children: [for (final cell in tableRows[row].cells) Padding(padding: const EdgeInsets.all(8), child: Text.rich(TextSpan(children: _inline(cell.text, tableRows[row].offset + cell.start,
                  row == 0 ? baseStyle.copyWith(fontWeight: FontWeight.bold) : baseStyle, tableCell: true))))]),
            ]));
        })));
        continue;
      }
      var text = line, start = offset, style = baseStyle;
      var align = TextAlign.left;
      if (widget.formatting && !_inCode) {
        final heading = projectHeading.firstMatch(line);
        if (heading != null) {
          text = heading.group(2)!; start += line.indexOf(text, heading.group(1)!.length);
          headingKey = GlobalKey();
          headings.add((title: text.trim(), key: headingKey));
          style = style.copyWith(fontSize: 14 + heading.group(1)!.length * 3.0, fontWeight: FontWeight.bold);
        } else if (line.startsWith('|') && line.endsWith('|') && line.length > 2) {
          final inner = line.substring(1, line.length - 1);
          final left = inner.startsWith(' '), right = inner.endsWith(' ');
          align = left && right ? TextAlign.center : left ? TextAlign.right : TextAlign.left;
          text = inner.trim(); start += 1 + inner.length - inner.trimLeft().length;
        }
      }
      final marker = widget.formatting && !_inCode && headingKey == null
          ? documentListMarker.firstMatch(line) : null;
      if (marker != null) {
        final number = marker.group(2);
        lines.add(Padding(
          padding: EdgeInsetsDirectional.only(start: (marker.group(1)!.length * 8.0).clamp(0.0, 64.0)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: number == null ? 24 : 32,
              child: Text(number == null ? '•' : '$number.', style: style)),
            Expanded(child: Text.rich(TextSpan(children:
              _inline(line.substring(marker.end), offset + marker.end, style)))),
          ]),
        ));
        offset += line.length + 1;
        continue;
      }
      lines.add(SizedBox(key: headingKey, width: double.infinity, child: Text.rich(TextSpan(children: _inline(text.isEmpty ? ' ' : text, start, style)), textAlign: align)));
      offset += line.length + 1;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (headings.isNotEmpty) ExpansionTile(
        title: const Text('목차'),
        children: [
          for (final heading in headings)
            ListTile(dense: true, title: Text(heading.title), onTap: () => _jump(heading.key)),
        ],
      ),
      ...lines,
      if (_numbers.isNotEmpty) ...[
        const Divider(),
        const Text('각주'),
        for (final entry in _numbers.entries) Padding(
            key: _noteKeys[entry.key],
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('[${entry.value}] ${_footnotes[entry.key]}'),
          ),
      ],
    ]);
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'element_binding.dart';
import 'label_links.dart';

String documentTitle(String text) {
  final first = text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).firstOrNull ?? '프로젝트';
  final heading = RegExp(r'^(={2,6})\s+(.+?)\s+\1$').firstMatch(first);
  return (heading?.group(2) ?? first).characters.take(60).toString();
}
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
  final _recognizers = <String, TapGestureRecognizer>{};
  List<InlineSpan> _inline(String text, int base, TextStyle style) {
    final result = <InlineSpan>[];
    var i = 0;
    final plain = StringBuffer();
    void flush() { if (plain.isNotEmpty) { result.add(TextSpan(text: plain.toString(), style: style)); plain.clear(); } }
    while (i < text.length) {
      final candidate = _linksAt[base + i];
      final link = candidate != null && candidate.end <= base + text.length ? candidate : null;
      if (link != null) {
        flush();
        final recognizer = _recognizers.putIfAbsent('${link.start}:${link.id}', () => TapGestureRecognizer())..onTap = () => openInlineLink(context, link.id);
        result.add(TextSpan(text: text.substring(i, link.end - base), style: style.merge(inlineLinkStyle(context, link.id)), recognizer: recognizer));
        i = link.end - base; continue;
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
          result.addAll(_inline(text.substring(i + 2, end), base + i + 2, next));
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
    _linksAt = {for (final b in widget.links) b.start: b};
    final keys = {for (final b in widget.links) '${b.start}:${b.id}'};
    for (final key in _recognizers.keys.where((key) => !keys.contains(key)).toList()) { _recognizers.remove(key)!.dispose(); }
    final baseStyle = widget.style ?? Theme.of(context).textTheme.bodyLarge!;
    final lines = <Widget>[];
    var offset = 0;
    for (final line in widget.text.split('\n')) {
      var text = line, start = offset, style = baseStyle;
      var align = TextAlign.left;
      if (widget.formatting) {
        final heading = RegExp(r'^(={2,6})\s+(.+?)\s+\1$').firstMatch(line);
        if (heading != null) {
          text = heading.group(2)!; start += line.indexOf(text, heading.group(1)!.length);
          style = style.copyWith(fontSize: 14 + heading.group(1)!.length * 3.0, fontWeight: FontWeight.bold);
        } else if (line.startsWith('|') && line.endsWith('|') && line.length > 2) {
          final inner = line.substring(1, line.length - 1);
          final left = inner.startsWith(' '), right = inner.endsWith(' ');
          align = left && right ? TextAlign.center : left ? TextAlign.right : TextAlign.left;
          text = inner.trim(); start += 1 + inner.length - inner.trimLeft().length;
        }
      }
      lines.add(SizedBox(width: double.infinity, child: Text.rich(TextSpan(children: _inline(text.isEmpty ? ' ' : text, start, style)), textAlign: align)));
      offset += line.length + 1;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: lines);
  }
}

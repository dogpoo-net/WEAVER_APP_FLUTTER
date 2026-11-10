import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'element_binding.dart';
import 'element_store.dart';
import 'word_badge.dart';

bool isInlineLink(String id) => id.startsWith('label:') || id.startsWith('url:');
ElementRecord? labelTarget(String id) => id.startsWith('label:')
  ? elements.records.values.where((r) => r.id == id.substring(6)).firstOrNull : null;
String? resolveLabelTarget(String target) {
  final uri = Uri.tryParse(target);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) return 'url:$uri';
  final matches = elements.records.values.where((r) => r.indexLabel.isNotEmpty && r.indexLabel == target).toList();
  return matches.length == 1 ? 'label:${matches.single.id}' : null;
}
Future<void> openInlineLink(BuildContext context, String id) async {
  if (id.startsWith('url:')) {
    final uri = Uri.tryParse(id.substring(4));
    if (uri != null && ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty) {
      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
      catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.'))); }
    }
  } else {
    final record = labelTarget(id);
    if (record != null) await showElementMetadata(context, record.text);
  }
}
TextStyle inlineLinkStyle(BuildContext context, String id) {
  final target = labelTarget(id);
  final color = target == null ? Theme.of(context).colorScheme.primary : wordColor(context, target.text);
  return TextStyle(color: color, decoration: TextDecoration.underline, decorationColor: color,
    decorationThickness: 2.5, fontWeight: FontWeight.w600);
}
/// A partially entered alias; only the target after the pipe is searched.
({int start, String display, String query})? pendingLabelLink(TextEditingValue value) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return null;
  final before = value.text.substring(0, value.selection.extentOffset);
  final match = RegExp(r'\[\[([^\[\]\n|]+)\|([^\[\]\n]*)$').firstMatch(before);
  return match == null ? null : (start: match.start, display: match.group(1)!, query: match.group(2)!);
}
class LabelTextController extends BoundTextController {
  LabelTextController([String text = '', Iterable<ElementBinding> links = const []])
    : super(text, links.where((b) => isInlineLink(b.id)));
  bool _parsing = false;
  final _recognizers = <String, TapGestureRecognizer>{};
  @override
  set value(TextEditingValue next) {
    super.value = next;
    if (!_parsing && (!value.composing.isValid || value.composing.isCollapsed)) completeLinks();
  }
  void completeLinks() {
    if (_parsing) return;
    _parsing = true;
    try {
      for (final match in RegExp(r'\[\[([^\[\]\n|]+)\|([^\[\]\n]+)\]\]').allMatches(text).toList().reversed) {
        final id = resolveLabelTarget(match.group(2)!.trim());
        if (id != null) bind(match.start, match.end, id, match.group(1)!);
      }
    } finally { _parsing = false; }
  }
  void insertLabel(ElementRecord record) {
    final pending = pendingLabelLink(value);
    final end = selection.isValid ? selection.end : text.length;
    final prefix = completionPrefix(value, elements.records.values.where((r) => r.indexLabel.isNotEmpty && elements.isSearchable(r.text)).map((r) => r.indexLabel).toList());
    final start = pending?.start ?? (end - prefix.length).clamp(0, end);
    bind(start, end, 'label:${record.id}', pending?.display ?? record.indexLabel);
  }
  void openAtCaret(BuildContext context) {
    if (!selection.isValid || !selection.isCollapsed) return;
    final hit = bindings.where((b) => b.start <= selection.extentOffset && selection.extentOffset < b.end).firstOrNull;
    if (hit != null) openInlineLink(context, hit.id);
  }
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (bindings.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final children = <InlineSpan>[];
    var offset = 0;
    void plain(int start, int end) {
      if (end <= start) return;
      final composing = value.composing;
      if (withComposing && composing.isValid && composing.start >= start && composing.end <= end && !composing.isCollapsed) {
        children.add(TextSpan(text: text.substring(start, composing.start)));
        children.add(TextSpan(text: text.substring(composing.start, composing.end), style: const TextStyle(decoration: TextDecoration.underline)));
        children.add(TextSpan(text: text.substring(composing.end, end)));
      } else { children.add(TextSpan(text: text.substring(start, end))); }
    }
    for (final link in bindings) {
      plain(offset, link.start);
      final recognizer = _recognizers.putIfAbsent(link.id, () => TapGestureRecognizer())..onTap = () => openInlineLink(context, link.id);
      children.add(TextSpan(text: text.substring(link.start, link.end), style: inlineLinkStyle(context, link.id), recognizer: recognizer));
      offset = link.end;
    }
    plain(offset, text.length);
    return TextSpan(style: style, children: children);
  }
  @override
  void dispose() { for (final r in _recognizers.values) { r.dispose(); } super.dispose(); }
}

/// Strip tags outside atomic links, retaining the adjusted link offsets.
({String text, Set<String> tags, List<ElementBinding> links}) cleanLinkedInput(LabelTextController controller) {
  var masked = controller.text;
  for (final b in controller.bindings.reversed) { masked = masked.replaceRange(b.start, b.end, 'x' * (b.end - b.start)); }
  final matches = RegExp(r'[ \t]*#([^\s#.,!?;:،؛؟()\[\]{}]+)', multiLine: true).allMatches(masked).toList();
  var text = controller.text;
  for (final m in matches.reversed) { text = text.replaceRange(m.start, m.end, ''); }
  final leading = text.length - text.trimLeft().length;
  int offset(int n) => n - matches.where((m) => m.end <= n).fold<int>(0, (sum, m) => sum + m.end - m.start) - leading;
  return (text: text.trim(), tags: {for (final m in matches) controller.text.substring(m.start, m.end).trim().substring(1).toLowerCase()},
    links: [for (final b in controller.bindings) ElementBinding(b.id, offset(b.start), offset(b.end))]);
}

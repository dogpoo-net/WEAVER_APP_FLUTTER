import 'package:flutter/material.dart';
import 'workspace_routes.dart';
import 'package:url_launcher/url_launcher.dart';
import 'element_binding.dart';
import 'element_store.dart';
import 'word_badge.dart';
import 'project_page.dart';
import 'document_syntax.dart';

abstract interface class InlineLinkDragSource { String? get linkKey; }
class InlineLinkDrag implements InlineLinkDragSource {
  const InlineLinkDrag(this.linkKey);
  @override final String linkKey;
}

bool isInlineLink(String id) => id.startsWith('label:') || id.startsWith('url:') || id.startsWith('project:');
ElementRecord? labelTarget(String id) => id.startsWith('label:')
  ? elements.records.values.where((r) => r.id == id.substring(6)).firstOrNull : null;
Iterable<WritingProject> get indexedProjects => elements.sources.keys.whereType<WritingProject>();
WritingProject? projectTarget(String id) => id.startsWith('project:')
  ? indexedProjects.where((p) => p.id == id.substring(8)).firstOrNull : null;
String assistTargetTitle(String key) => projectTarget(key)?.title ?? elements.records[key]?.title ?? key;
List<String> labelAssistTargets({WritingProject? excludeProject}) => [
  for (final project in indexedProjects) if (project != excludeProject) 'project:${project.id}',
  ...elements.visibleWords.where(isLabelAssistTarget),
  ...elements.visibleWords.where((key) => !isLabelAssistTarget(key)),
];
bool isLabelAssistTarget(String key) => elements.records[key]?.indexLabel.trim().isNotEmpty ?? false;
bool assistTargetMatches(String key, String query) {
  final needle = query.trim().toLowerCase();
  return matchesWord(assistTargetTitle(key), query) ||
      matchesWord(elements.records[key]?.indexLabel ?? '', query) ||
      (projectTarget(key)?.content ?? elements.records[key]?.text ?? '').toLowerCase().contains(needle);
}
String? resolveLabelTarget(String target) {
  final uri = Uri.tryParse(target);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) return 'url:$uri';
  final matches = [
    for (final r in elements.records.values) if (r.indexLabel.isNotEmpty && r.indexLabel == target) 'label:${r.id}',
    for (final p in indexedProjects) if (p.title == target) 'project:${p.id}',
  ];
  return matches.length == 1 ? matches.single : null;
}
Future<void> openInlineLink(BuildContext context, String id) async {
  if (id.startsWith('url:')) {
    final uri = Uri.tryParse(id.substring(4));
    if (uri != null && ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty) {
      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
      catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.'))); }
    }
  } else if (id.startsWith('project:')) {
    if(openWorkspaceDocument!=null){await openWorkspaceDocument!(id.substring(8));return;}
    final project = projectTarget(id);
    if (project != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectPage(
        project: project, projects: indexedProjects.toList(), onChanged: () async { elements.projectChanged(project); })));
    }
  } else {
    final record = labelTarget(id);
    if (record != null) await showElementMetadata(context, record.text);
  }
}
TextStyle inlineLinkStyle(BuildContext context, String id, {bool hovered = false}) {
  final target = labelTarget(id);
  final color = target == null ? const Color(0xFFFF9800) : wordColor(context, target.text);
  final memo = id.startsWith('label:');
  return TextStyle(color: color, decoration: memo || hovered ? TextDecoration.underline : TextDecoration.none, decorationColor: color,
    decorationStyle: memo ? TextDecorationStyle.dotted : TextDecorationStyle.solid,
    decorationThickness: 1, fontWeight: FontWeight.normal);
}
/// A partially entered alias; only the target after the pipe is searched.
({int start, String display, String query})? pendingLabelLink(TextEditingValue value) {
  if (!value.selection.isValid || !value.selection.isCollapsed) return null;
  final before = value.text.substring(0, value.selection.extentOffset);
  final match = RegExp(r'\[\[([^\[\]\n|]+)\|([^\[\]\n]*)$').firstMatch(before);
  return match == null ? null : (start: match.start, display: match.group(1)!, query: match.group(2)!);
}
/// An unfinished double-bracket link already supplies its own title syntax.
bool hasOpenLinkMarkup(TextEditingValue value) {
  final end = value.selection.isValid ? value.selection.start : value.text.length;
  return RegExp(r'\[\[[^\]\n]*$').hasMatch(value.text.substring(0, end));
}

Future<void> insertAssistedLink(BuildContext context, LabelTextController controller, String key, {bool alwaysPrompt = false, bool replaceQuery = true}) async {
  final before = controller.value;
  if (!alwaysPrompt && hasOpenLinkMarkup(before)) { controller.insertTarget(key); return; }
  final fallback = projectTarget(key)?.title ?? elements.records[key]?.text ?? key;
  String title = '';
  final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
    title: const Text('링크 타이틀'),
    content: TextField(key: const ValueKey('link-title-input'), autofocus: true,
      decoration: InputDecoration(hintText: fallback, helperText: '비워두면 메모 본문 또는 문서 제목을 표시합니다.'),
      onChanged: (value) => title = value, onSubmitted: (value) => Navigator.pop(context, value)),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      TextButton(onPressed: () => Navigator.pop(context, title), child: const Text('확인'))]));
  if (!context.mounted || result == null || controller.text != before.text) return;
  controller.selection = before.selection;
  controller.insertTarget(key, display: result.trim().isEmpty ? fallback : result.trim(), complete: replaceQuery);
}

class LabelTextController extends BoundTextController {
  LabelTextController([String text = '', Iterable<ElementBinding> links = const []])
    : super(text, links.where((b) => isInlineLink(b.id)));
  bool _parsing = false;
  String? _hoveredLink;
  @override
  set value(TextEditingValue next) {
    super.value = next;
    if (!_parsing && (!value.composing.isValid || value.composing.isCollapsed)) completeLinks();
  }
  void loadDocument(String text, Iterable<ElementBinding> links, {TextSelection? selection}) {
    bindings = [];
    super.value = TextEditingValue(text: text, selection: selection ?? TextSelection.collapsed(offset: text.length));
    bindings = links.where((b) => isInlineLink(b.id)).toList();
    notifyListeners();
  }
  void completeLinks() {
    if (_parsing) return;
    _parsing = true;
    try {
      for (final match in RegExp(r'\[\[([^\[\]\n|]+)\|([^\[\]\n]+)\]\]').allMatches(text).toList().reversed) {
        if (codeMarkup.allMatches(text).any((code) => code.start <= match.start && match.start < code.end)) continue;
        final id = resolveLabelTarget(match.group(2)!.trim());
        if (id != null) bind(match.start, match.end, id, match.group(1)!);
      }
    } finally { _parsing = false; }
  }
  void insertLabel(ElementRecord record) => _insert('label:${record.id}', record.title);
  void insertTarget(String key, {String? display, bool complete = true}) {
    final project = projectTarget(key);
    if (project != null) { _insert('project:${project.id}', project.title, display: display, complete: complete); return; }
    final record = elements.records[key];
    if (record != null) _insert('label:${record.id}', record.title, display: display, complete: complete);
  }
  void _insert(String id, String title, {String? display, bool complete = true}) {
    if (selection.isValid && !selection.isCollapsed) {
      final selected = selection;
      if (bindings.any((b) => selected.start < b.end && selected.end > b.start &&
          !(selected.start <= b.start && selected.end >= b.end))) { return; }
      bindings.removeWhere((b) => selected.start <= b.start && selected.end >= b.end);
      bind(selected.start, selected.end, id, display ?? text.substring(selected.start, selected.end));
      return;
    }
    final pending = complete ? pendingLabelLink(value) : null;
    final end = selection.isValid ? selection.end : text.length;
    final prefix = complete ? completionPrefix(value, labelAssistTargets().map(assistTargetTitle).toList()) : '';
    final open = complete ? RegExp(r'\[\[[^\]\n]*$').firstMatch(text.substring(0, end)) : null;
    final start = pending?.start ?? open?.start ?? (end - prefix.length).clamp(0, end);
    bind(start, end, id, display ?? pending?.display ?? title);
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
      children.add(TextSpan(text: text.substring(link.start, link.end), style: inlineLinkStyle(context, link.id, hovered: _hoveredLink == link.id),
        mouseCursor: SystemMouseCursors.click,
        onEnter: (_) { _hoveredLink = link.id; notifyListeners(); },
        onExit: (_) { _hoveredLink = null; notifyListeners(); }));
      offset = link.end;
    }
    plain(offset, text.length);
    return TextSpan(style: style, children: children);
  }
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

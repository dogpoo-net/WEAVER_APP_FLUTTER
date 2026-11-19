import 'package:flutter/material.dart';
import 'workspace_routes.dart';
import 'package:url_launcher/url_launcher.dart';
import 'element_binding.dart';
import 'element_store.dart';
import 'word_badge.dart';
import 'project_page.dart';
import 'document_syntax.dart';
import 'document_diagnostics.dart';

abstract interface class InlineLinkDragSource { String? get linkKey; }
class InlineLinkDrag implements InlineLinkDragSource {
  const InlineLinkDrag(this.linkKey);
  @override final String linkKey;
}

bool isInlineLink(String id) => id.startsWith('label:') || id.startsWith('url:') || id.startsWith('project:');
ElementRecord? labelTarget(String id) => id.startsWith('label:')
  ? elements.byId(id.substring(6)) : null;
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
TextStyle inlineLinkStyle(BuildContext context, String id, {
  bool hovered = false,
  bool markMissing = false,
}) {
  final target = labelTarget(id);
  final missing = markMissing && (
    (id.startsWith('label:') && (target == null || target.deletedAt != null)) ||
    (id.startsWith('project:') && projectTarget(id) == null)
  );
  final Color color;
  if (missing) {
    color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF7587)
        : const Color(0xFFB4233D);
  } else if (target == null) {
    color = const Color(0xFFFF9800);
  } else if (target.hiddenFromSearch) {
    color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF808080)
        : const Color(0xFF505050);
  } else {
    color = wordColor(context, target.text);
  }
  final memo = id.startsWith('label:');
  return TextStyle(color: color, decoration: memo || hovered || missing ? TextDecoration.underline : TextDecoration.none, decorationColor: color,
    decorationStyle: memo ? TextDecorationStyle.dotted : TextDecorationStyle.solid,
    decorationThickness: 1, fontWeight: FontWeight.normal);
}
/// Display-only links: no recognizers, hover callbacks, or navigation.
TextSpan passiveLinkedText(BuildContext context, String text, Iterable<ElementBinding> links) {
  if (links.isEmpty) return TextSpan(text: text);
  final spans = <InlineSpan>[];
  var offset = 0;
  final ordered = links.toList()..sort((a, b) => a.start.compareTo(b.start));
  for (final link in ordered) {
    if (link.start < offset || link.end <= link.start || link.end > text.length) continue;
    if (link.start > offset) spans.add(TextSpan(text: text.substring(offset, link.start)));
    spans.add(TextSpan(text: text.substring(link.start, link.end), style: inlineLinkStyle(context, link.id)));
    offset = link.end;
  }
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return TextSpan(children: spans);
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
  final document = projectTarget(key);
  final alias = pendingLabelLink(before)?.display.trim();
  if (!alwaysPrompt && hasOpenLinkMarkup(before) && (document != null || (alias != null && alias.isNotEmpty))) { controller.insertTarget(key); return; }
  final fallback = document?.title ?? elements.records[key]?.text ?? key;
  String title = ''; String? error;
  final result = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) {
    void submit(String value) {
      if (document == null && value.trim().isEmpty) { update(() => error = '링크 제목을 입력해주세요.'); return; }
      Navigator.pop(context, value);
    }
    return AlertDialog(
      title: const Text('링크 타이틀'),
      content: TextField(key: const ValueKey('link-title-input'), autofocus: true,
        decoration: InputDecoration(hintText: document?.title, errorText: error,
          helperText: document == null ? '링크를 보여줄 제목을 설정하세요.' : '비워두면 문서 제목으로 입력됩니다.'),
        onChanged: (value) { title = value; if (error != null) update(() => error = null); }, onSubmitted: submit),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () => submit(title), child: const Text('확인'))]);
  }));
  if (!context.mounted || result == null || controller.text != before.text) return;
  controller.selection = before.selection;
  controller.insertTarget(key, display: result.trim().isEmpty ? fallback : result.trim(), complete: replaceQuery);
}

class LabelTextController extends BoundTextController {
  LabelTextController([String text = '', Iterable<ElementBinding> links = const []])
    : super(text, links.where((b) => isInlineLink(b.id)));
  bool _parsing = false;
  String? _hoveredLink;
  ValueChanged<String?>? onLinkHover;
  bool editingDocument = false;
  final _syntax = DocumentSyntaxDiagnostics();
  DocumentDiagnosticReport? onSyntaxDiagnostic;
  List<DocumentDiagnostic> get syntaxDiagnostics => editingDocument ? _syntax.forSource(text) : const [];

  void _setHoveredLink(String? id) {
    if (_hoveredLink == id) return;
    _hoveredLink = id;
    onLinkHover?.call(id);
    notifyListeners();
  }
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
    if (hit != null && !(editingDocument && hit.id.startsWith('label:'))) {
      openInlineLink(context, hit.id);
    }
  }
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final diagnostics = syntaxDiagnostics;
    if (bindings.isEmpty && diagnostics.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final children = <InlineSpan>[];
    var offset = 0;
    var diagnosticIndex = 0;
    void append(int start, int end, {TextStyle? textStyle, ElementBinding? link}) {
      while (start < end) {
        while (diagnosticIndex < diagnostics.length && diagnostics[diagnosticIndex].end <= start) {
          diagnosticIndex++;
        }
        final next = diagnosticIndex < diagnostics.length ? diagnostics[diagnosticIndex] : null;
        final issue = next != null && next.contains(start) ? next : null;
        final boundary = issue?.end ?? next?.start ?? end;
        final stop = boundary < end ? boundary : end;
        children.add(TextSpan(
          text: text.substring(start, stop),
          style: issue != null
              ? (textStyle ?? const TextStyle()).merge(documentDiagnosticStyle(context))
              : textStyle,
          mouseCursor: link == null ? null
              : editingDocument ? SystemMouseCursors.text : SystemMouseCursors.click,
          onEnter: issue == null && link == null ? null : (event) {
            if (link != null) _setHoveredLink(link.id);
            if (issue != null) onSyntaxDiagnostic?.call(issue.message, event.position);
          },
          onExit: issue == null && link == null ? null : (event) {
            if (link != null && _hoveredLink == link.id) _setHoveredLink(null);
            if (issue != null) onSyntaxDiagnostic?.call(null, event.position);
          },
        ));
        start = stop;
      }
    }
    void plain(int start, int end) {
      if (end <= start) return;
      final composing = value.composing;
      if (withComposing && composing.isValid && composing.start >= start &&
          composing.end <= end && !composing.isCollapsed) {
        append(start, composing.start);
        append(composing.start, composing.end, textStyle: const TextStyle(decoration: TextDecoration.underline));
        append(composing.end, end);
      } else {
        append(start, end);
      }
    }
    for (final link in bindings) {
      plain(offset, link.start);
      final hovered = _hoveredLink == link.id;
      final linkStyle = inlineLinkStyle(context, link.id, hovered: hovered);
      append(link.start, link.end, link: link,
        textStyle: hovered ? linkStyle.copyWith(decorationStyle: TextDecorationStyle.solid) : linkStyle);
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

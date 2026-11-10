import 'package:flutter/material.dart';

class ElementBinding {
  const ElementBinding(this.id, this.start, this.end);
  final String id;
  final int start, end;
  Map<String, dynamic> toJson() => {'id': id, 'start': start, 'end': end};
}

/// Text remains copyable; linked ranges can only be removed as a whole.
class BoundTextController extends TextEditingController {
  BoundTextController(String text, Iterable<ElementBinding> links) : bindings = List.of(links), super(text: text);
  List<ElementBinding> bindings;
  @override
  set value(TextEditingValue next) {
    if (next.text == text) { super.value = next; return; }
    var start = 0;
    while (start < text.length && start < next.text.length && text[start] == next.text[start]) { start++; }
    var end = text.length, nextEnd = next.text.length;
    while (end > start && nextEnd > start && text[end - 1] == next.text[nextEnd - 1]) { end--; nextEnd--; }
    if (nextEnd == start && end > start) {
      // A native deletion touching any part of a link removes the entire token.
      final originalStart = start, originalEnd = end;
      for (final link in bindings) {
        if (start < link.end && end > link.start) {
          if (link.start < start) start = link.start;
          if (link.end > end) end = link.end;
        }
      }
      nextEnd = start;
      if (start != originalStart || end != originalEnd) {
        next = TextEditingValue(text: text.replaceRange(start, end, ''),
          selection: TextSelection.collapsed(offset: start));
      }
    }
    final delta = nextEnd - end;
    for (final link in bindings) {
      final overlaps = start < link.end && end > link.start || start == end && start > link.start && start < link.end;
      if (overlaps && !(start <= link.start && end >= link.end)) return;
    }
    bindings = [for (final link in bindings)
      if (!(start <= link.start && end >= link.end && start != end))
        ElementBinding(link.id, link.start >= end ? link.start + delta : link.start,
          link.end > start && link.start >= end ? link.end + delta : link.end)];
    super.value = next;
  }
  bool bind(int start, int end, String id, String word, {bool newlineAfter = false}) {
    if (bindings.any((link) => start < link.end && end > link.start || start > link.start && start < link.end)) return false;
    final appendLine = newlineAfter && !word.endsWith('\n') && (end >= text.length || text[end] != '\n');
    final replacement = word + (appendLine ? '\n' : '');
    final delta = replacement.length - (end - start);
    bindings = [for (final link in bindings) ElementBinding(link.id,
      link.start >= end ? link.start + delta : link.start, link.start >= end ? link.end + delta : link.end),
      ElementBinding(id, start, start + word.length)]..sort((a, b) => a.start.compareTo(b.start));
    final updated = text.replaceRange(start, end, replacement);
    final offset = start + replacement.length;
    super.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset:
      newlineAfter && !appendLine && offset < updated.length && updated[offset] == '\n' ? offset + 1 : offset));
    return true;
  }
  void sync(Map<String, String> records) {
    for (final link in List.of(bindings).reversed) {
      final replacement = records[link.id];
      if (replacement == null) { bindings.removeWhere((b) => b.id == link.id); continue; }
      if (text.substring(link.start, link.end) == replacement) continue;
      final delta = replacement.length - (link.end - link.start);
      final updated = text.replaceRange(link.start, link.end, replacement);
      bindings = [for (final b in bindings)
        if (b.id == link.id && b.start == link.start && b.end == link.end) ElementBinding(b.id, b.start, b.start + replacement.length)
        else ElementBinding(b.id, b.start >= link.end ? b.start + delta : b.start, b.start >= link.end ? b.end + delta : b.end)];
      final offset = selection.isValid ? selection.extentOffset : updated.length;
      super.value = TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: offset.clamp(0, updated.length)));
    }
  }
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (bindings.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final children = <InlineSpan>[];
    var offset = 0;
    for (final link in bindings) {
      children.add(TextSpan(text: text.substring(offset, link.start)));
      children.add(TextSpan(text: text.substring(link.start, link.end), style: TextStyle(
        color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        decoration: TextDecoration.underline)));
      offset = link.end;
    }
    children.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: children);
  }
}

  List<ElementBinding> taggedTextBindings(BoundTextController controller) {
    final text = controller.text;
    final pattern = RegExp(r'(^|\s)#[^\s#.,!?;:،؛؟()\[\]{}]+', multiLine: true);
    final matches = pattern.allMatches(text).toList();
    int offset(int position) {
      var removed = 0;
      for (final match in matches) {
        final start = match.start + match.group(1)!.length;
        removed += (position - start).clamp(0, match.end - start);
      }
      final stripped = text.replaceAllMapped(pattern, (m) => m.group(1)!);
      final leading = stripped.length - stripped.trimLeft().length;
      return position - removed - leading;
    }
    return [for (final link in controller.bindings)
      if (!matches.any((m) => m.start < link.end && m.end > link.start))
        ElementBinding(link.id, offset(link.start), offset(link.end))];
  }

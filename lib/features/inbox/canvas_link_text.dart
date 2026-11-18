import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'element_binding.dart';
import 'label_links.dart';

/// Canvas links use text hit testing, leaving card dragging to the parent.
class CanvasLinkText extends StatefulWidget {
  const CanvasLinkText({super.key, required this.text, required this.links, required this.enabled, this.style});
  final String text;
  final List<ElementBinding> links;
  final bool enabled;
  final TextStyle? style;
  @override
  State<CanvasLinkText> createState() => _CanvasLinkTextState();
}
class _CanvasLinkTextState extends State<CanvasLinkText> {
  final _taps = <String, TapGestureRecognizer>{};
  bool _opening = false;
  String? _hovered;
  Future<void> _open(String id) async {
    if (_opening) return;
    _opening = true;
    try { await openInlineLink(context, id); } finally { _opening = false; }
  }
  @override
  void dispose() { for (final tap in _taps.values) { tap.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final active = <String>{};
    final children = <InlineSpan>[];
    var offset = 0;
    final links = List<ElementBinding>.of(widget.links)..sort((a,b)=>a.start.compareTo(b.start));
    for (final link in links) {
      if (link.start < offset || link.end <= link.start || link.end > widget.text.length) continue;
      if (link.start > offset) children.add(TextSpan(text: widget.text.substring(offset, link.start)));
      final key = '${link.id}:${link.start}:${link.end}';
      TapGestureRecognizer? tap;
      if (widget.enabled) {
        active.add(key);
        tap = _taps.putIfAbsent(key, TapGestureRecognizer.new)..onTap = () => _open(link.id);
      }
      final hovered = widget.enabled && _hovered == key;
      final style = inlineLinkStyle(context, link.id, hovered: hovered);
      children.add(TextSpan(text: widget.text.substring(link.start, link.end),
        style: hovered ? style.copyWith(decorationStyle: TextDecorationStyle.solid) : style,
        onEnter: widget.enabled ? (_) { if (mounted) setState(() => _hovered = key); } : null,
        onExit: widget.enabled ? (_) { if (mounted && _hovered == key) setState(() => _hovered = null); } : null,
        recognizer: tap, mouseCursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer));
      offset = link.end;
    }
    for (final key in _taps.keys.where((key)=>!active.contains(key)).toList()) { _taps.remove(key)!.dispose(); }
    if (!active.contains(_hovered)) _hovered = null;
    if (offset < widget.text.length) children.add(TextSpan(text: widget.text.substring(offset)));
    return Text.rich(TextSpan(children: children), softWrap: true, overflow: TextOverflow.clip, style: widget.style);
  }
}

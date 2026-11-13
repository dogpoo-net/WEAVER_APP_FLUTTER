import 'package:flutter/material.dart';

/// Paint beside the real EditableText rather than estimating wrapped line height.
class DocumentLineNumbers extends StatefulWidget {
  const DocumentLineNumbers({super.key, required this.controller, required this.scroll, required this.child});
  final TextEditingController controller;
  final ScrollController scroll;
  final Widget child;
  @override
  State<DocumentLineNumbers> createState() => _DocumentLineNumbersState();
}
class _DocumentLineNumbersState extends State<DocumentLineNumbers> {
  final field = GlobalKey(), gutter = GlobalKey();
  final layoutReady = ValueNotifier(0);
  @override void dispose() { layoutReady.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) layoutReady.value++; });
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 42, child: ClipRect(child: CustomPaint(key: gutter,
        painter: _LineNumbers(field, gutter, widget.controller, widget.scroll, layoutReady,
          Theme.of(context).colorScheme.onSurfaceVariant, MediaQuery.textScalerOf(context))))),
      Expanded(child: KeyedSubtree(key: field, child: widget.child)),
    ]);
  }
}
class _LineNumbers extends CustomPainter {
  _LineNumbers(this.field, this.gutter, this.controller, ScrollController scroll, Listenable layoutReady, this.color, this.scaler)
    : super(repaint: Listenable.merge([controller, scroll, layoutReady]));
  final GlobalKey field, gutter;
  final TextEditingController controller;
  final Color color;
  final TextScaler scaler;
  String? _cachedText;
  List<int> _starts = [0];
  @override
  void paint(Canvas canvas, Size size) {
    EditableTextState? editor;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) { editor = element.state as EditableTextState; return; }
      element.visitChildren(visit);
    }
    final context = field.currentContext;
    if (context == null) return;
    visit(context as Element);
    final render = editor?.renderEditable;
    final box = gutter.currentContext?.findRenderObject() as RenderBox?;
    if (render == null || box == null || !render.hasSize) return;
    final origin = box.globalToLocal(render.localToGlobal(Offset.zero));
    if (_cachedText != controller.text) {
      _cachedText = controller.text;
      _starts = [0, for (var i = 0; i < controller.text.length; i++) if (controller.text.codeUnitAt(i) == 10) i + 1];
    }
    final starts = _starts;
    double top(int index) => origin.dy + render.getLocalRectForCaret(TextPosition(offset: starts[index])).top;
    var low = 0, high = starts.length;
    while (low < high) { final middle = (low + high) ~/ 2; if (top(middle) < -render.preferredLineHeight) { low = middle + 1; } else { high = middle; } }
    for (var i = low; i < starts.length; i++) {
      final y = top(i); if (y > size.height) break;
      final painter = TextPainter(text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: 12, color: color)),
        textDirection: TextDirection.ltr, textScaler: scaler)..layout();
      painter.paint(canvas, Offset(size.width - painter.width - 8, y + (render.preferredLineHeight - painter.height) / 2));
      painter.dispose();
    }
  }
  @override
  bool shouldRepaint(covariant _LineNumbers oldDelegate) => true;
}

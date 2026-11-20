import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum DocumentLineAction { comment, delete, moveUp, moveDown, copyUp, copyDown }

const documentLineShortcuts = {
  SingleActivator(LogicalKeyboardKey.slash, control: true):
      DocumentLineAction.comment,
  SingleActivator(LogicalKeyboardKey.keyD, control: true):
      DocumentLineAction.delete,
  SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
      DocumentLineAction.moveUp,
  SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
      DocumentLineAction.moveDown,
  SingleActivator(LogicalKeyboardKey.arrowUp, control: true, alt: true):
      DocumentLineAction.copyUp,
  SingleActivator(LogicalKeyboardKey.arrowDown, control: true, alt: true):
      DocumentLineAction.copyDown,
};

typedef DocumentLineSlice = ({int start, int end, int destination});
typedef DocumentLineEdit = ({
  int start,
  int end,
  String replacement,
  TextSelection selection,
  List<DocumentLineSlice> slices,
});

DocumentLineEdit? editDocumentLines(
  String text,
  TextSelection selection,
  DocumentLineAction action,
) {
  if (!selection.isValid || selection.end > text.length) return null;
  int lineStart(int offset) =>
      offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  int lineEnd(int offset) {
    final end = text.indexOf('\n', offset);
    return end == -1 ? text.length : end;
  }

  final start = lineStart(selection.start);
  final end = lineEnd(
    selection.isCollapsed ? selection.end : selection.end - 1,
  );
  final block = text.substring(start, end);
  switch (action) {
    case DocumentLineAction.comment:
      final uncomment = block.startsWith('<!--') && block.endsWith('-->');
      final value = uncomment
          ? block.substring(4, block.length - 3)
          : '<!--$block-->';
      int offset(int original) =>
          start +
          (original - start + (uncomment ? -4 : 4)).clamp(0, value.length);
      return (
        start: start,
        end: end,
        replacement: value,
        selection: TextSelection(
          baseOffset: offset(selection.baseOffset),
          extentOffset: offset(selection.extentOffset),
        ),
        slices: [
          if (uncomment)
            (start: start + 4, end: end - 3, destination: start)
          else
            (start: start, end: end, destination: start + 4),
        ],
      );
    case DocumentLineAction.delete:
      final from = end == text.length && start > 0 ? start - 1 : start;
      return (
        start: from,
        end: end < text.length ? end + 1 : end,
        replacement: '',
        selection: TextSelection.collapsed(offset: from),
        slices: const [],
      );
    case DocumentLineAction.copyUp:
    case DocumentLineAction.copyDown:
      final down = action == DocumentLineAction.copyDown;
      return (
        start: start,
        end: end,
        replacement: '$block\n$block',
        selection: down ? _shift(selection, block.length + 1) : selection,
        slices: [
          (start: start, end: end, destination: start),
          (start: start, end: end, destination: start + block.length + 1),
        ],
      );
    case DocumentLineAction.moveUp:
      if (start == 0) return null;
      final previous = lineStart(start - 1);
      return (
        start: previous,
        end: end,
        replacement: '$block\n${text.substring(previous, start - 1)}',
        selection: _shift(selection, previous - start),
        slices: [
          (start: start, end: end, destination: previous),
          (
            start: previous,
            end: start - 1,
            destination: previous + block.length + 1,
          ),
        ],
      );
    case DocumentLineAction.moveDown:
      if (end == text.length) return null;
      final next = lineEnd(end + 1);
      return (
        start: start,
        end: next,
        replacement: '${text.substring(end + 1, next)}\n$block',
        selection: _shift(selection, next - end),
        slices: [
          (start: end + 1, end: next, destination: start),
          (start: start, end: end, destination: start + next - end),
        ],
      );
  }
}

TextSelection _shift(TextSelection selection, int delta) => TextSelection(
  baseOffset: selection.baseOffset + delta,
  extentOffset: selection.extentOffset + delta,
);

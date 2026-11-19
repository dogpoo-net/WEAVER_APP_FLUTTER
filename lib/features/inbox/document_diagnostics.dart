import 'dart:async';

import 'package:flutter/material.dart';

import 'document_syntax.dart';

class DocumentDiagnostic {
  const DocumentDiagnostic(this.start, this.end, this.line, this.message);

  final int start, end, line;
  final String message;

  bool contains(int offset) => start <= offset && offset < end;
}

typedef DocumentDiagnosticReport = void Function(
  String? message,
  Offset position,
);

typedef DocumentSyntaxRule = Iterable<DocumentDiagnostic> Function(
  String source,
);

class DocumentSyntaxDiagnostics {
  static const List<DocumentSyntaxRule> _rules = [_singleTitle];
  String? _source;
  List<DocumentDiagnostic> _issues = const [];

  List<DocumentDiagnostic> forSource(String source) {
    if (source != _source) {
      _source = source;
      _issues = [for (final rule in _rules) ...rule(source)]
        ..sort((a, b) => a.start.compareTo(b.start));
    }
    return _issues;
  }

  static Iterable<DocumentDiagnostic> _singleTitle(String source) sync* {
    final masked = DocumentComments(source).maskedText;
    final code = codeMarkup.allMatches(masked).iterator;
    var hasCode = code.moveNext();
    var seenTitle = false;
    var start = 0;
    var lineNumber = 0;
    for (final line in masked.split('\n')) {
      final end = start + line.length;
      while (hasCode && code.current.end <= start) {
        hasCode = code.moveNext();
      }
      // Inline code is valid in a title. Ignore titles that start inside code.
      if (!hasCode || code.current.start > start) {
        final heading = projectHeading.firstMatch(line.trimRight());
        if (heading?.group(1)?.length == 6 &&
            heading!.group(2)!.trim().isNotEmpty) {
          if (seenTitle) {
            yield DocumentDiagnostic(
              start,
              end,
              lineNumber,
              '문서의 제목은 하나만 가질 수 있습니다.',
            );
          }
          seenTitle = true;
        }
      }
      start = end + 1;
      lineNumber++;
    }
  }
}

TextStyle documentDiagnosticStyle(BuildContext context) => TextStyle(
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.wavy,
  decorationColor: Theme.of(context).colorScheme.error,
  decorationThickness: 1.5,
);

/// Hover and touch use the same popup, anchored to the offending text.
class DocumentDiagnosticTooltip {
  OverlayEntry? _entry;
  Timer? _timeout;

  void show(
    BuildContext context,
    String message,
    Offset globalPosition, {
    bool touch = false,
  }) {
    hide();
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = overlay.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final point = box.globalToLocal(globalPosition);
    _entry = OverlayEntry(
      builder: (context) {
        const width = 290.0;
        final colors = Theme.of(context).colorScheme;
        return Positioned(
          left: (point.dx + 10).clamp(
            8.0,
            (box.size.width - width - 8).clamp(8.0, double.infinity),
          ),
          top: (point.dy + 20).clamp(
            8.0,
            (box.size.height - 70).clamp(8.0, double.infinity),
          ),
          child: IgnorePointer(
            child: Material(
              color: colors.inverseSurface,
              borderRadius: BorderRadius.circular(6),
              elevation: 3,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (box.size.width - 16).clamp(0.0, width),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: TextStyle(
                        color: colors.onInverseSurface,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    if (touch) _timeout = Timer(const Duration(seconds: 4), hide);
  }

  void hide() {
    _timeout?.cancel();
    _timeout = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

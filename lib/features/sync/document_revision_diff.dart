import 'package:flutter/material.dart';

class RevisionLine {
  const RevisionLine(this.before, this.after, this.operation, this.parts);
  final int? before, after;
  final String operation;
  final List<({String text, bool changed})> parts;
  String get text => parts.map((p) => p.text).join();
}

/// Existing character diffs are grouped at shared newline boundaries. A replaced
/// paragraph retains both versions, including changed characters within each line.
List<RevisionLine> revisionLines(List<dynamic> chunks) {
  final rows = <RevisionLine>[];
  final left = <RevisionLine>[], right = <RevisionLine>[];
  var l = <({String text, bool changed})>[], r = <({String text, bool changed})>[];
  var ln = 1, rn = 1;
  void flush() {
    bool same(RevisionLine a, RevisionLine b) => a.text == b.text && !a.parts.any((p) => p.changed) && !b.parts.any((p) => p.changed);
    void equal(RevisionLine a, RevisionLine b) => rows.add(RevisionLine(a.before, b.after, 'equal', a.parts));
    var first = 0;
    while (first < left.length && first < right.length && same(left[first], right[first])) { equal(left[first], right[first]); first++; }
    var lastLeft = left.length, lastRight = right.length;
    while (lastLeft > first && lastRight > first && same(left[lastLeft - 1], right[lastRight - 1])) { lastLeft--; lastRight--; }
    rows.addAll(left.sublist(first, lastLeft)); rows.addAll(right.sublist(first, lastRight));
    for (var i = lastLeft, j = lastRight; i < left.length; i++, j++) { equal(left[i], right[j]); }
    left.clear(); right.clear();
  }

  for (final chunk in chunks) {
    final operation = chunk['operation'] as String;
    final pieces = (chunk['text'] as String).split('\n');
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].isNotEmpty) {
        if (operation != 'insert') l.add((text: pieces[i], changed: operation == 'delete'));
        if (operation != 'delete') r.add((text: pieces[i], changed: operation == 'insert'));
      }
      if (i < pieces.length - 1) {
        if (operation == 'delete') l.add((text: '', changed: true));
        if (operation == 'insert') r.add((text: '', changed: true));
        if (operation != 'insert') { left.add(RevisionLine(ln++, null, 'delete', l)); l = []; }
        if (operation != 'delete') { right.add(RevisionLine(null, rn++, 'insert', r)); r = []; }
        if (operation == 'equal') flush();
      }
    }
  }
  if (l.isNotEmpty) left.add(RevisionLine(ln, null, 'delete', l));
  if (r.isNotEmpty) right.add(RevisionLine(null, rn, 'insert', r));
  flush();
  return rows;
}

class DocumentRevisionDiff extends StatelessWidget {
  const DocumentRevisionDiff({super.key, required this.chunks});
  final List<dynamic> chunks;
  @override
  Widget build(BuildContext context) {
    final rows = revisionLines(chunks);
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.all(8), child: Text('이전 / 이후 줄번호 · − 삭제 · + 추가\n교체된 문장은 삭제·추가로 함께 표시합니다.')),
      const Divider(height: 1),
      Expanded(child: SelectionArea(child: ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
        final row = rows[index];
        final tint = row.operation == 'insert' ? Colors.green : Colors.red;
        return Container(color: row.operation == 'equal' ? null : tint.withValues(alpha: .12),
          padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 46, child: Text('${row.before ?? ''}', textAlign: TextAlign.right, style: TextStyle(color: colors.onSurfaceVariant))),
            SizedBox(width: 46, child: Text('${row.after ?? ''}', textAlign: TextAlign.right, style: TextStyle(color: colors.onSurfaceVariant))),
            SizedBox(width: 24, child: Text(row.operation == 'equal' ? ' ' : row.operation == 'insert' ? '+' : '−', textAlign: TextAlign.center)),
            Expanded(child: Text.rich(TextSpan(children: [for (final part in row.parts)
              TextSpan(text: part.text, style: TextStyle(backgroundColor: part.changed ? tint.withValues(alpha: .28) : null))]),
              style: const TextStyle(fontFamily: 'monospace', height: 1.5))),
            const SizedBox(width: 8),
          ]));
      }))),
    ]);
  }
}

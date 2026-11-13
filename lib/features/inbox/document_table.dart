import 'package:flutter/material.dart';

typedef TableCellSource = ({String text, int start});
List<TableCellSource>? tableCells(String line) {
  if (!line.startsWith('|') || !line.endsWith('|')) return null;
  final cells = <TableCellSource>[];
  var start = 1, escaped = false;
  for (var i = 1; i < line.length; i++) {
    if (line[i] == '|' && !escaped) {
      final raw = line.substring(start, i);
      cells.add((text: raw.trim(), start: start + raw.length - raw.trimLeft().length)); start = i + 1;
    }
    if (line[i] == '\\' && !escaped) { escaped = true; } else { escaped = false; }
  }
  return cells.isEmpty ? null : cells;
}
bool tableSeparator(String line, int columns) {
  final cells = tableCells(line);
  return cells != null && cells.length == columns && cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.text));
}
String tableMarkdown(List<List<String>> rows) {
  String row(List<String> cells) => '| ${cells.map((cell) => cell.replaceAll('\\', '\\\\').replaceAll('|', r'\|').replaceAll('\n', '<br>')).join(' | ')} |';
  return [row(rows.first), row(List.filled(rows.first.length, '---')), ...rows.skip(1).map(row)].join('\n');
}

Future<String?> showDocumentTableDialog(BuildContext context) => showDialog<String>(context: context, builder: (_) => const _TableDialog());
class _TableDialog extends StatefulWidget {
  const _TableDialog();
  @override State<_TableDialog> createState() => _TableDialogState();
}
class _TableDialogState extends State<_TableDialog> {
  int rows = 3, columns = 3;
  final values = <String, String>{};
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('표 삽입'),
    content: SizedBox(width: 480, height: (MediaQuery.sizeOf(context).height * .45).clamp(180.0, 340.0), child: Column(children: [
      IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(30, 30), maximumSize: const Size(30, 30), padding: EdgeInsets.zero, iconSize: 18, tapTargetSize: MaterialTapTargetSize.shrinkWrap)), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(tooltip: '행 줄이기', onPressed: rows > 1 ? () => setState(() => rows--) : null, icon: const Icon(Icons.remove)),
        Text('본문 $rows행'), IconButton(tooltip: '행 추가', onPressed: rows < 20 ? () => setState(() => rows++) : null, icon: const Icon(Icons.add)),
        IconButton(tooltip: '열 줄이기', onPressed: columns > 1 ? () => setState(() => columns--) : null, icon: const Icon(Icons.remove)),
        Text('$columns열'), IconButton(tooltip: '열 추가', onPressed: columns < 10 ? () => setState(() => columns++) : null, icon: const Icon(Icons.add)),
      ])),
      const Text('첫 행은 제목입니다. 삽입 후 본문의 표 문법으로 수정할 수 있습니다.'),
      const SizedBox(height: 8),
      Expanded(child: SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: columns * 120, child: Column(children: [
        for (var row = 0; row <= rows; row++) Row(children: [for (var col = 0; col < columns; col++)
          SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(2), child: TextFormField(key: ValueKey('table-cell-$row-$col'),
            style: const TextStyle(fontSize: 12),
            initialValue: values['$row:$col'] ?? '', onChanged: (value) => values['$row:$col'] = value,
            decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: const OutlineInputBorder(), hintText: row == 0 ? '제목 ${col + 1}' : '${row + 1}행 ${col + 1}열'))))]),
      ]))))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      TextButton(onPressed: () => Navigator.pop(context, tableMarkdown([for (var row = 0; row <= rows; row++) [for (var col = 0; col < columns; col++) values['$row:$col'] ?? '']])), child: const Text('삽입'))]);
}

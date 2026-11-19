import 'package:flutter/material.dart';

TextStyle documentCodeStyle(BuildContext context) => TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  height: 1.45,
  color: Theme.of(context).colorScheme.onSurface,
);

BoxDecoration documentCodeDecoration(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: colors.surfaceContainerLow,
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(6),
  );
}

class DocumentCodeBlock extends StatelessWidget {
  const DocumentCodeBlock(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: documentCodeDecoration(context),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(code.isEmpty ? ' ' : code, style: documentCodeStyle(context)),
    ),
  );
}

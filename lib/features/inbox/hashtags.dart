class TaggedInput {
  const TaggedInput(this.text, this.tags);
  final String text;
  final Set<String> tags;
}

TaggedInput parseTaggedInput(String input) {
  final tags = <String>{};
  final pattern = RegExp(r'[ \t]*#([^\s#.,!?;:،؛؟()\[\]{}]+)', multiLine: true);
  final text = input.replaceAllMapped(pattern, (match) {
    tags.add(match.group(1)!.toLowerCase());
    return '';
  }).trim();
  return TaggedInput(text, tags);
}

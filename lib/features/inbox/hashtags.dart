class TaggedInput {
  const TaggedInput(this.text, this.tags);
  final String text;
  final Set<String> tags;
}

TaggedInput parseTaggedInput(String input) {
  final tags = <String>{};
  final pattern = RegExp(r'(^|\s)#([^\s#.,!?;:،؛؟()\[\]{}]+)', multiLine: true);
  final text = input.replaceAllMapped(pattern, (match) {
    tags.add(match.group(2)!.toLowerCase());
    return match.group(1)!;
  }).trim();
  return TaggedInput(text, tags);
}

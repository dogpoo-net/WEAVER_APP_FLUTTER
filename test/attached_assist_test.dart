import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/word_badge.dart';

void main() {
  String prefix(String text) => completionPrefix(TextEditingValue(text: text,
    selection: TextSelection.collapsed(offset: text.length)), ['독서', '작은 생각']);
  test('attached words match the longest eligible suffix', () {
    expect(prefix('오늘독'), '독');
    expect(prefix('오늘독서'), '독서');
    expect(prefix('오늘작은 생각'), '작은 생각');
    expect(prefix('독'), '독');
    expect(prefix('오늘무관'), '오늘무관');
  });
}

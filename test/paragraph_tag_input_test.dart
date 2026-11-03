import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/paragraph_editor.dart';
import 'package:weaver/features/inbox/paragraph_tag_input.dart';

void main() {
  TextEditingValue value(String text) => TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  test('completed hashtags leave prose and cursor intact, with no IME interference', () {
    final extracted = takeCompletedParagraphTags(value('오늘 #독서 #독서 #Idea 다음 글'));
    expect(extracted.tags, {'독서', 'idea'});
    expect(extracted.value.text, '오늘 다음 글');
    expect(extracted.value.selection.extentOffset, extracted.value.text.length);
    expect(takeCompletedParagraphTags(value('C# #아직')).tags, isEmpty);
    final composing = value('#한글 ').copyWith(composing: const TextRange(start: 1, end: 3));
    expect(takeCompletedParagraphTags(composing).value, composing);
    expect(takeCompletedParagraphTags(composing).tags, isEmpty);
    final middle = takeCompletedParagraphTags(const TextEditingValue(text: '앞 #태그 뒤', selection: TextSelection.collapsed(offset: 6)));
    expect(middle.value.text, '앞 뒤');
    expect(middle.value.selection.extentOffset, 2);
    expect(takeCompletedParagraphTags(value('첫줄\n#태그\n다음줄')).value.text, '첫줄\n\n다음줄');
  });

  test('tag field prefixes tokens and spaces, while allowing pending marker deletion', () {
    const formatter = HashtagInputFormatter();
    expect(formatter.formatEditUpdate(value(''), value('독서 아이디어 ')).text, '#독서 #아이디어 #');
    expect(formatter.formatEditUpdate(value('#독서'), value('#독서  ')).text, '#독서 #');
    expect(formatter.formatEditUpdate(value('#독서 #'), value('#독서 ')).text, '#독서');
    final composing = value('한').copyWith(composing: const TextRange(start: 0, end: 1));
    expect(formatter.formatEditUpdate(value(''), composing), composing);
  });

  testWidgets('paragraph moves a completed hashtag immediately and saves it separately', (tester) async {
    List<Paragraph>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { saved = await Navigator.push<List<Paragraph>>(context,
        MaterialPageRoute(builder: (_) => const ParagraphEditor(words: [], initialTags: {'기존'}))); },
      child: const Text('작성'),
    )))));
    await tester.tap(find.text('작성'));
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('paragraph-0'));
    final tags = find.byKey(const ValueKey('paragraph-tags'));
    await tester.enterText(body, '본문 #독서 ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(body).controller!.text, '본문 ');
    expect(tester.widget<TextField>(tags).controller!.text, '#기존 #독서');
    await tester.enterText(tags, '#기존 #독서 새태그 ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(tags).controller!.text, '#기존 #독서 #새태그 #');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(saved!.single.text, '본문');
    expect(saved!.single.tags, {'기존', '독서', '새태그'});
  });

  testWidgets('project prose keeps inline hashtags untouched', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParagraphEditor(projectEditing: true, words: [])));
    final field = find.byKey(const ValueKey('paragraph-0'));
    await tester.enterText(field, '프로젝트 #본문 ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '프로젝트 #본문 ');
    expect(find.byKey(const ValueKey('paragraph-tags')), findsNothing);
  });
}

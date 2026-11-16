import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/inbox/element_store.dart';
import 'package:weaver/features/inbox/label_links.dart';
import 'package:weaver/features/inbox/project_page.dart';
void main(){
 for(final document in [false,true]){testWidgets('link title validation (document=$document)',(tester)async{
  elements.clear();final memo=elements.add('메모 본문');final doc=WritingProject([],[],name:'문서 제목')..document='======문서 제목======';elements.indexProject(doc);final controller=LabelTextController();
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>insertAssistedLink(context,controller,document?'project:${doc.id}':memo.text),child:const Text('링크'))))));
  await tester.tap(find.text('링크'));await tester.pumpAndSettle();expect(find.text(document?'비워두면 문서 제목으로 입력됩니다.':'링크를 보여줄 제목을 설정하세요.'),findsOneWidget);
  await tester.tap(find.text('확인'));await tester.pumpAndSettle();
  if(document){expect(controller.text,'문서 제목');expect(find.byType(AlertDialog),findsNothing);}
  else {expect(controller.text,isEmpty);expect(find.text('링크 제목을 입력해주세요.'),findsOneWidget);
   await tester.enterText(find.byKey(const ValueKey('link-title-input')),'   ');await tester.testTextInput.receiveAction(TextInputAction.done);await tester.pumpAndSettle();expect(find.byType(AlertDialog),findsOneWidget);
   await tester.enterText(find.byKey(const ValueKey('link-title-input')),'메모 제목');await tester.testTextInput.receiveAction(TextInputAction.done);await tester.pumpAndSettle();expect(controller.text,'메모 제목');expect(controller.bindings.single.id,'label:${memo.id}');
  }
  await tester.pumpWidget(const SizedBox());controller.dispose();
 });}
}

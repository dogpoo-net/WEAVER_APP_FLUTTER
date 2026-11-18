import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/workspace_picker.dart';
void main(){
 testWidgets('suspended spaces remain visible with red reasons and cannot be opened',(tester)async{
  await tester.pumpWidget(MaterialApp(home:WorkspacePicker(workspaces:[
   {'workspaceId':'a','name':'Cancelled space','role':'editor','sharingSuspended':true,'subscriptionEndReason':'cancelled'},
   {'workspaceId':'b','name':'Expired space','role':'viewer','sharingSuspended':true,'subscriptionEndReason':'expired'},
   {'workspaceId':'c','name':'Free space','role':'viewer','sharingSuspended':true,'subscriptionEndReason':'free'},
   {'workspaceId':'d','name':'Paid space','role':'editor','sharingSuspended':false},
  ],selected:null,request:(a,b)async=>{},onCatalog:(_){})));
  for(final reason in ['구독 취소','구독 기한 만료','소유자 무료 플랜']){
   final text=tester.widget<Text>(find.text(reason));
   expect(text.style!.color,Theme.of(tester.element(find.text(reason))).colorScheme.error);
   final tile=find.ancestor(of:find.text(reason),matching:find.byType(ListTile));
   expect(tester.widget<ListTile>(tile).onTap,isNull);
  }
  final active=find.ancestor(of:find.text('Paid space',findRichText:true),matching:find.byType(ListTile));
  expect(tester.widget<ListTile>(active).onTap,isNotNull);
 });
}

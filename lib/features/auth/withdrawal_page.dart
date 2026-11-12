import 'package:flutter/material.dart';
import 'google_auth.dart';

class WithdrawalPage extends StatefulWidget {
 const WithdrawalPage({super.key, required this.auth});
 final GoogleAuthController auth;
 @override State<WithdrawalPage> createState()=>_WithdrawalPageState();
}
class _WithdrawalPageState extends State<WithdrawalPage> {
 final code=TextEditingController();
 Map<String,dynamic>? data;
 final choices=<String,String>{};
 final deleteConsent=<String>{};
 bool busy=false,confirmed=false,sent=false;
 String? error;
 @override void initState(){super.initState();run(load);}
 @override void dispose(){code.dispose();super.dispose();}
 Future<void> load()async{final result=await widget.auth.emailApi.profile('withdrawal/preview');if(mounted)setState(()=>data=result);}
 Future<void> run(Future<void> Function() action)async{
  if(busy)return;setState((){busy=true;error=null;});
  try{await action();}catch(e){if(mounted)setState(()=>error=e.toString());}
  finally{if(mounted)setState(()=>busy=false);}
 }
 bool get ready=>confirmed && sent && RegExp(r'^\d{8}$').hasMatch(code.text) && data!=null &&
   (data!['workspaces'] as List).every((w){final id=w['workspaceId'] as String;return choices[id]!=null && (choices[id]!='delete'||deleteConsent.contains(id));});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('회원탈퇴')),body:ListView(padding:const EdgeInsets.all(20),children:[
  const Text('계정과 자료를 영구 삭제합니다.',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
  const SizedBox(height:12),
  const Text('계정 정보, 문서·생각·메모상자·배치·변경 이력, 사진·음성·프로필 사진, 소셜 연결 및 모든 기기 세션이 삭제됩니다. 복구할 수 없습니다. 이 기기에 저장된 해당 계정의 자료도 삭제합니다.'),
  const SizedBox(height:12),
  if(data!=null)...[
   Text(data!['retention'] as String),const SizedBox(height:12),Text(data!['sharedNotice'] as String),
   const SizedBox(height:12),
   const Text('소셜 서비스 자체의 계정은 삭제되지 않습니다. 해당 서비스에 남은 앱 접근 권한은 그 서비스의 연결 관리에서도 해제할 수 있습니다. 다른 기기의 오프라인 저장본은 해당 기기에서도 삭제해주세요.'),
   const Divider(),
   for(final w in data!['workspaces'] as List)...[
    Text('워크스페이스 · ${(w['workspaceId'] as String).substring(0,8)}'),
    Text('참여자 ${(w['members'] as List).length+1}명 · 저장된 자료 ${w['bytes']}바이트'),
    DropdownButtonFormField<String>(key:ValueKey('withdraw-workspace-${w['workspaceId']}'),initialValue:choices[w['workspaceId']],isExpanded:true,
     decoration:const InputDecoration(labelText:'소유권 이전 또는 삭제'),
     items:[const DropdownMenuItem(value:'delete',child:Text('자료 전체 삭제')),
      for(final member in w['members'] as List)DropdownMenuItem(value:member['userId'] as String,child:Text('${member['name']??member['email']}에게 소유권 이전',overflow:TextOverflow.ellipsis))],
     onChanged:busy?null:(value)=>setState((){choices[w['workspaceId'] as String]=value!;deleteConsent.remove(w['workspaceId']);})),
    if(choices[w['workspaceId']]=='delete')CheckboxListTile(contentPadding:EdgeInsets.zero,value:deleteConsent.contains(w['workspaceId']),onChanged:busy?null:(v)=>setState((){if(v==true){deleteConsent.add(w['workspaceId'] as String);}else{deleteConsent.remove(w['workspaceId']);}}),title:const Text('다른 참여자가 작성한 자료를 포함해 이 공간 전체를 삭제하는 데 동의합니다.')),
    const SizedBox(height:16),
   ],
   OutlinedButton(onPressed:busy?null:()=>run(()async{await widget.auth.emailApi.profile('withdrawal/request');if(mounted)setState(()=>sent=true);}),child:Text(sent?'인증메일 다시 보내기':'가입 이메일로 탈퇴 인증코드 받기')),
   if(sent)TextField(controller:code,enabled:!busy,keyboardType:TextInputType.number,maxLength:8,decoration:const InputDecoration(labelText:'탈퇴 인증코드 8자리'),onChanged:(_)=>setState((){})),
   CheckboxListTile(contentPadding:EdgeInsets.zero,value:confirmed,onChanged:busy?null:(v)=>setState(()=>confirmed=v??false),title:const Text('삭제 대상과 보관 안내를 확인했으며, 복구할 수 없다는 점에 동의합니다.')),
   FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(context).colorScheme.error),onPressed:busy||!ready?null:()=>run(()async{
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('정말 탈퇴하시겠습니까?'),content:const Text('선택한 소유권 이전 및 영구 삭제를 실행합니다. 되돌릴 수 없습니다.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),TextButton(onPressed:()=>Navigator.pop(context,true),child:const Text('탈퇴'))]));
    if(yes!=true)return;
    await widget.auth.withdrawAccount({'code':code.text,'confirmed':true,'transfers':{for(final entry in choices.entries)if(entry.value!='delete')entry.key:entry.value},'deleteWorkspaces':choices.entries.where((e)=>e.value=='delete').map((e)=>e.key).toList()});
   }),child:const Text('회원탈퇴')),
  ],
  const SizedBox(height:16),const SelectableText('개인정보 문의: 도그푸(Dogpoo) · privacy@dogpoo.net'),
  if(busy)const LinearProgressIndicator(),
  if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  if(data==null&&!busy)TextButton(onPressed:()=>run(load),child:const Text('다시 불러오기')),
 ]));
}

import 'package:flutter/material.dart';
import '../auth/google_auth.dart';
import '../auth/profile_page.dart';
import '../sync/notification_inbox.dart';
import 'keyboard_dismiss.dart';

/// The home header is also available before the first workspace exists.
class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MainAppBar({super.key, required this.leading, this.auth, this.onNotification, this.onTitle, this.startupSyncPending = false});
  final Widget leading;
  final GoogleAuthController? auth;
  final Future<void> Function(Map<String,dynamic>)? onNotification;
  final bool startupSyncPending;
  final VoidCallback? onTitle;
  @override Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override Widget build(BuildContext context) => AppBar(
    leading:leading,centerTitle:false,
    title:GestureDetector(onTap:onTitle,child:const Text('WEAVER',style:TextStyle(fontSize:16,fontWeight:FontWeight.w700,letterSpacing:3))),
    actions:[
      const KeyboardDismissAction(),
      if(auth?.identity!=null)...[
        NotificationBell(key:ValueKey('notifications-${auth!.identity!.id}'),request:auth!.emailApi.workspace,onOpen:onNotification,startupSyncPending:startupSyncPending),
        IconButton(tooltip:'프로필',onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ProfilePage(auth:auth!))),icon:ProfileAvatar(auth:auth)),
      ],
      const SizedBox(width:12),
    ],
  );
}

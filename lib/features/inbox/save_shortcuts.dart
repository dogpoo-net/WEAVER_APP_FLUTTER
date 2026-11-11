import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
class SaveShortcuts extends StatelessWidget {
  const SaveShortcuts({super.key,required this.onSave,required this.child});
  final VoidCallback onSave;final Widget child;
  @override Widget build(BuildContext context)=>CallbackShortcuts(bindings:{
    const SingleActivator(LogicalKeyboardKey.keyS,control:true):onSave,
    const SingleActivator(LogicalKeyboardKey.keyS,meta:true):onSave,
  },child:Focus(autofocus:true,child:child));
}

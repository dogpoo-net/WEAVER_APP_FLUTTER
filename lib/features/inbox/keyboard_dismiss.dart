import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

class KeyboardDismissAction extends StatelessWidget {
  const KeyboardDismissAction({super.key});
  @override
  Widget build(BuildContext context) => MediaQuery.viewInsetsOf(context).bottom > 0
    ? IconButton(tooltip: '키보드 내리기', onPressed: dismissKeyboard,
        icon: const Icon(Icons.keyboard_hide_outlined))
    : const SizedBox.shrink();
}

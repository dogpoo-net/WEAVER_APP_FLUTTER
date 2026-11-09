import 'package:flutter/material.dart';
Widget googleSignInButton({required VoidCallback? onPressed}) => OutlinedButton(
  onPressed: onPressed,
  child: const Text('Google로 로그인'),
);

import 'package:flutter/material.dart';
import 'login_provider_button.dart';
Widget googleSignInButton({required VoidCallback? onPressed, double width = loginButtonMaxWidth}) =>
  LoginProviderButton(label: 'Google로 로그인', icon: Icons.login, onPressed: onPressed);

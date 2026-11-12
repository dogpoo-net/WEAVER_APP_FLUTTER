import 'package:flutter/material.dart';
import 'login_provider_button.dart';
Widget googleSignInButton({required VoidCallback? onPressed, double width = loginButtonMaxWidth}) =>
  SizedBox(width: width, child: LoginProviderButton(label: 'Google로 로그인', symbolAsset: 'assets/branding/social/google.png', onPressed: onPressed));

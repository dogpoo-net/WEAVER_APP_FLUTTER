import 'package:flutter/material.dart';
import 'login_provider_button.dart';
Widget googleSignInButton({required VoidCallback? onPressed, double width = loginButtonMaxWidth, String label = 'Google로 로그인'}) =>
  SizedBox(width: width, child: LoginProviderButton(label: label, symbolAsset: 'assets/branding/social/google.png', onPressed: onPressed));

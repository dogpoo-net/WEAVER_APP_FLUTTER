import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google;
Widget googleSignInButton({required VoidCallback? onPressed}) => SizedBox(
  height: 44, width: 280,
  child: IgnorePointer(ignoring: onPressed == null, child: google.renderButton(
    configuration: google.GSIButtonConfiguration(minimumWidth: 280, locale: 'ko'),
  )),
);

import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google;
import 'login_provider_button.dart';
Widget googleSignInButton({required VoidCallback? onPressed, double width = loginButtonMaxWidth}) => SizedBox(
  height: loginButtonHeight, width: width,
  child: IgnorePointer(ignoring: onPressed == null, child: google.renderButton(
    configuration: google.GSIButtonConfiguration(minimumWidth: width, locale: 'ko',
      theme: google.GSIButtonTheme.outline, size: google.GSIButtonSize.large,
      shape: google.GSIButtonShape.rectangular, logoAlignment: google.GSIButtonLogoAlignment.left,
      text: google.GSIButtonText.signinWith),
  )),
);

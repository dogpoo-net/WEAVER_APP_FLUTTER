import 'package:flutter/material.dart';

const loginButtonHeight = 40.0;
const loginButtonMaxWidth = 320.0;

class LoginProviderButton extends StatelessWidget {
  const LoginProviderButton({super.key, required this.label, this.icon, this.symbolAsset, this.onPressed});
  final String label;
  final IconData? icon;
  final String? symbolAsset;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: loginButtonHeight,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFF4F4F4),
        foregroundColor: const Color(0xFF1F1F1F), disabledForegroundColor: const Color(0xFF737373),
        side: BorderSide(color: onPressed == null ? const Color(0xFFDADCE0) : const Color(0xFF747775)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Row(textDirection: TextDirection.ltr, children: [const SizedBox(width: 32),
        Expanded(child: Text(label, textAlign: TextAlign.center)), const SizedBox(width: 12),
        if (symbolAsset != null) Image.asset(symbolAsset!, width: 20, height: 20, fit: BoxFit.contain, excludeFromSemantics: true)
        else Icon(icon, size: 20),
      ]),
    ),
  );
}

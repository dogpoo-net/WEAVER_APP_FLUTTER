import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

Widget photoImage(
  Uint8List bytes, {
  BoxFit fit = BoxFit.contain,
  int? cacheWidth,
  String? semanticLabel,
  ImageErrorWidgetBuilder? errorBuilder,
  double? height,
  double? width,
}) {
  if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '<svg ') {
    return SvgPicture.memory(
      bytes,
      fit: fit,
      semanticsLabel: semanticLabel,
      height: height,
      width: width,
    );
  }
  return Image.memory(
    bytes,
    fit: fit,
    cacheWidth: cacheWidth,
    semanticLabel: semanticLabel,
    errorBuilder: errorBuilder,
    height: height,
    width: width,
  );
}

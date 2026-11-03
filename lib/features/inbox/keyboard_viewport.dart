import 'package:flutter/widgets.dart';
import 'keyboard_viewport_stub.dart'
    if (dart.library.js_interop) 'keyboard_viewport_web.dart' as browser;

/// Web may shrink its viewport while retaining an IME inset from the old size.
double effectiveKeyboardInset(MediaQueryData media, {double? visibleHeight}) {
  final visible = visibleHeight ?? browser.visibleHeight();
  if (visible == null) return media.viewInsets.bottom;
  return media.viewInsets.bottom.clamp(
    0.0,
    (media.size.height - visible).clamp(0.0, media.size.height),
  );
}

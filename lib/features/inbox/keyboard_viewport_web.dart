import 'dart:js_interop';

@JS('window.visualViewport')
external VisualViewport? get _viewport;

extension type VisualViewport(JSObject _) implements JSObject {
  external double get height;
  external double get offsetTop;
}

double? visibleHeight() {
  final viewport = _viewport;
  return viewport == null ? null : viewport.height + viewport.offsetTop;
}

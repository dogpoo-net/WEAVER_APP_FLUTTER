import 'oauth_window_handle.dart';
import 'package:web/web.dart' as web;
class OAuthWindow implements OAuthWindowHandle {
  final web.Window? _window = web.window.open('about:blank', '_blank', 'width=520,height=720');
  @override
  bool get closed => _window == null || _window.closed;
  @override
  Future<void> navigate(String url) async {
    if (_window == null) throw StateError('로그인 팝업을 허용해주세요.');
    _window.opener = null;
    _window.location.href = url;
  }
  @override
  void close() => _window?.close();
}

import 'package:web/web.dart' as web;
class OAuthWindow {
  final web.Window? _window = web.window.open('about:blank', '_blank', 'width=520,height=720');
  bool get closed => _window == null || _window.closed;
  Future<void> navigate(String url) async {
    if (_window == null) throw StateError('로그인 팝업을 허용해주세요.');
    _window.opener = null;
    _window.location.href = url;
  }
  void close() => _window?.close();
}

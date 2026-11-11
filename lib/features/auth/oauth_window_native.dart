import 'oauth_window_handle.dart';
import 'package:url_launcher/url_launcher.dart';
class OAuthWindow implements OAuthWindowHandle {
  @override
  bool get closed => false;
  @override
  Future<void> navigate(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw StateError('브라우저를 열지 못했습니다.');
  }
  @override
  void close() {}
}

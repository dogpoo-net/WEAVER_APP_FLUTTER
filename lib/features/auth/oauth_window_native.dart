import 'package:url_launcher/url_launcher.dart';
class OAuthWindow {
  bool get closed => false;
  Future<void> navigate(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw StateError('브라우저를 열지 못했습니다.');
  }
  void close() {}
}

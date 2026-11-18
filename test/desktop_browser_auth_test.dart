import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/auth/google_auth.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'login_presentation_test.dart' show NoGoogle;
class BrowserApi extends EmailAuthApi {
 final calls = <String>[];
 @override Future<Map<String,dynamic>?> loginBrowser(String provider, {bool link = false}) async {
 calls.add('$provider:$link'); return null;
 }
}
void main() {
 test('Windows routes Google and Kakao login through browser without SDK', () async {
 debugDefaultTargetPlatformOverride = TargetPlatform.windows;
 addTearDown(() => debugDefaultTargetPlatformOverride = null);
 final api = BrowserApi(); final auth = GoogleAuthController(NoGoogle(), emailApi: api);
 expect(auth.googleReady, isTrue); expect(auth.kakaoAvailable, isTrue);
 await auth.signIn(); await auth.signInWithKakao();
 expect(api.calls, ['google:false', 'kakao:false']); expect(auth.busy, isFalse);
 auth.dispose();
 });
}

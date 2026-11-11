import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'email_auth.dart';

// Public platform identifiers, never a REST Client Secret.
const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY', defaultValue: 'c94f1617112a7f6f29fd26b529c4c180');
const kakaoJavaScriptAppKey = String.fromEnvironment('KAKAO_JAVASCRIPT_APP_KEY', defaultValue: '8beafb8eedd186a745fa11e15f6f8076');
abstract class KakaoAuthClient {
  bool get configured;
  Future<String?> accessToken();
}
class _TransientKakaoTokens implements TokenManager {
  OAuthToken? token;
  @override Future<void> setToken(OAuthToken token) async { this.token = token; }
  @override Future<OAuthToken?> getToken() async => token;
  @override Future<void> clear() async { token = null; }
}
class SdkKakaoAuthClient implements KakaoAuthClient {
  @override bool get configured => kIsWeb ? kakaoJavaScriptAppKey.isNotEmpty :
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) && kakaoNativeAppKey.isNotEmpty;
  @override Future<String?> accessToken() async {
    if (!configured) throw const EmailAuthFailure('카카오 로그인은 웹·Android·iOS에서 지원합니다.');
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey, javaScriptAppKey: kakaoJavaScriptAppKey, loggingEnabled: false);
    final tokens = _TransientKakaoTokens();
    TokenManagerProvider.instance.manager = tokens;
    try {
      OAuthToken token;
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        try { token = await UserApi.instance.loginWithKakaoTalk(); }
        on PlatformException catch (e) {
          if (e.code == 'CANCELED') return null;
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else { token = await UserApi.instance.loginWithKakaoAccount(); }
      return token.accessToken;
    } on KakaoClientException catch (e) {
      if (e.reason == ClientErrorCause.cancelled) return null;
      throw const EmailAuthFailure('카카오 로그인에 실패했습니다. 다시 시도해주세요.');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw const EmailAuthFailure('카카오 로그인 설정과 연결을 확인해주세요.');
    } catch (_) { throw const EmailAuthFailure('카카오 로그인에 실패했습니다. 다시 시도해주세요.'); }
    finally { await tokens.clear(); }
  }
}

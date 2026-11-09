# Google 로그인 설정 및 서버 연결

웹과 Android는 `google_sign_in` 공식 플러그인을 사용한다. 웹은 Google Identity Services가 렌더링한 버튼을 사용한다. 앱에는 비밀키를 넣지 않는다.

## OAuth 설정

1. Google Cloud에서 동의 화면을 설정한다. 테스트 상태라면 테스트 사용자도 등록한다.
2. **웹 애플리케이션** OAuth 클라이언트를 생성한다. 승인된 JavaScript 원본에 `https://dogpoo-net.github.io`를 등록한다(저장소 경로 제외). 로컬 테스트는 고정 포트의 `http://localhost:포트`를 별도로 등록한다.
3. 현재 사용자가 제공한 웹 클라이언트 ID를 기본값으로 설정했다. 일반 API 키나 비밀키가 아니며 공개 가능한 식별자이다. 전용 클라이언트로 변경할 때 웹 클라이언트 ID를 GitHub 저장소 Actions 변수 `GOOGLE_WEB_CLIENT_ID`에 설정한다. Pages workflow가 빌드에 전달한다.
4. **Android** OAuth 클라이언트를 같은 프로젝트에 생성한다. 패키지는 `net.dogpoo.weaver`, SHA-1은 실제 서명 인증서의 지문이다. 디버그, 배포 서명, Play 앱 서명이 다르면 각각 등록한다. 현재 Gradle release는 debug signing이므로 실제 배포 전에 정식 서명 설정이 필요하다.
5. Android 빌드에도 동일한 **웹** 클라이언트 ID를 전달한다. 플러그인은 이것을 `serverClientId`로 사용한다. Android 클라이언트 ID를 여기에 넣지 않는다. Firebase나 google-services.json은 이 방식에서 필수가 아니다.

```sh
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
flutter build appbundle --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

OAuth가 미구성된 클라이언트에서는 로그인 안내와 비활성 버튼을 표시하고 작업 화면을 열지 않는다. 현재 기본 ID를 사용하려면 Google Cloud에서 WEAVER 원본을 허용해야 한다. 기존 데이터는 삭제하지 않는다. 실제 계정 로그인은 클라이언트 ID와 원본/서명 등록 후 확인해야 한다. iOS 로그인은 이번 범위에 포함하지 않는다.

## 현재 인증 경계

`GoogleAuthClient`는 SDK 어댑터, `GoogleAuthController`는 로그인 상태를 담당한다. 토큰은 메모리에만 보관하며 로그나 SharedPreferences에 기록하지 않는다. 로그인 성공 시 작업 화면을 열고, 로그아웃 시 중첩된 화면까지 제거한다. SDK의 lightweight authentication으로 기존 Google 세션의 복원을 시도한다. 로컬 데이터는 현재 기기 단위이며 아직 계정별 데이터가 아니다. Google 로그인 UI는 서버 접근 권한 검증을 대신하지 않는다.

## 백엔드 제공 시 필요한 계약

- HTTPS 인증 엔드포인트: Google ID 토큰을 받아 서명, issuer, audience, 만료를 검증하고 자체 세션 발급. 클라이언트가 보내는 사용자 ID/이메일을 신뢰하지 않는다. 웹은 HttpOnly Secure 쿠키 및 CSRF/CORS 정책, Android는 만료/갱신 가능한 세션 규격을 정한다.
- 사용자별 생각·태그·상자·폴더·프로젝트·연결 CRUD와 변경 커서/버전, 삭제 tombstone, 재시도 멱등키. 매 입력마다 전체 스냅샷을 보내지 않는다.
- 사진·음성 파일 업로드/다운로드/삭제 API. 기존 Hive 파일과 JSON 메타데이터를 함께 이관해야 한다.
- 최초 로컬 데이터 가져오기: 계정 소유권 확인과 중복 방지, 서버 데이터와 병합/충돌 규칙. 다른 계정으로 로그인했을 때 같은 기기의 데이터를 자동으로 올리지 않는다.
- 테마와 캔버스 배치의 동기화 범위 결정.

엔드포인트가 아직 없으므로 현재는 서버 전송이나 동기화 완료 표시를 하지 않는다. 로컬 저장은 유지하며, 서버 계약 확정 후 인증 교환 → 계정별 저장 분리 → 최초 가져오기 → 동작별 증분 동기화 순서로 연결한다.

기존 포럼의 웹 클라이언트를 재사용할 수 있으나 동의 화면/관리 범위를 분리하려면 WEAVER 전용 클라이언트가 권장된다. GIS 버튼 방식이므로 `/oauth` 라우트나 redirect URL은 이번 앱에 추가하지 않는다. 클라이언트 비밀키는 앱/워크플로/저장소에 넣지 않는다.

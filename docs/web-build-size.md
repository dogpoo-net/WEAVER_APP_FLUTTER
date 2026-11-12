# 웹 빌드 크기와 정리

2026-11-12 로컬 릴리스 산출물 기준 약 52.2 MiB에서 28.4 MiB로 감소(약 46%).
이는 배포 디렉터리의 비압축 합계이며 실제 브라우저 최초 전송량이나 APK 크기가 아닙니다.

## 빌드

```sh
flutter pub get
bash tool/build_web.sh
```

추가 Flutter 옵션은 스크립트 뒤에 전달합니다. GitHub Pages 워크플로도 동일 스크립트를 사용하지만 실행은 기존처럼 수동입니다. 기본 배포 대상은 도그푸 서버입니다.

- dart2js + CanvasKit 빌드에서 쓰지 않는 skwasm/wimp 렌더러, WebParagraph 변형, 디버깅 symbols만 제거합니다.
- Chromium용 경량 CanvasKit과 Safari/Firefox 등에서 필요한 기본 CanvasKit은 모두 유지합니다.
- 부트스트랩은 로컬 CanvasKit을 사용하고 WebParagraph를 명시적으로 비활성화합니다.
- WebAssembly 앱 빌드나 과거 캐싱 서비스워커가 감지되면 정리를 거부합니다. 향후 빌드 방식을 바꾸면 스크립트를 함께 검토해야 합니다.
- 전체 한글 폰트(약 10 MiB)는 글자 지원을 유지하기 위해 보존합니다. 폰트 부분집합을 임의로 만들지 않습니다.
- `google_sign_in_web` 직접 선언만 제거했습니다. `google_sign_in`의 필수 전이 의존성은 유지합니다.
- `cupertino_icons`는 앱 직접 import는 없지만 Flutter 내부 참조가 빌드에서 확인되어 유지합니다.
- 웹/앱에서 같아진 Google 버튼 코드는 한 파일로 통합했습니다. 사용하지 않는 동기화 타이머 필드와 정리 코드를 제거했습니다.
- `lib/main.dart`에서 조건부 import/export까지 추적한 결과 파일 단위 미참조 소스는 없었습니다. 나머지 직접 패키지는 실제 사용 중입니다.

추가로 용량을 줄이려면 한글 폰트 전달 방식, 서버 전송 압축/캐싱, 기능별 지연 로딩을 별도로 측정해야 합니다. 디렉터리 크기 감소 자체를 실행 속도 향상 수치로 해석하지 않습니다.

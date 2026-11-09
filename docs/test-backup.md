# 임시 서버 백업 / 휴지통

환경설정의 데이터 저장하기 / 데이터 가져오기로 사용자가 직접 실행한다. 자동 동기화는 하지 않는다.

- 저장: `POST https://api.dogpoo.net/dogpoo/weaver/api/test/insertWeaverTestData`
  - JSON: `account` = 현재 Google 계정 이메일, `jsonData` = 백업 JSON 문자열
- 가져오기: `POST https://api.dogpoo.net/dogpoo/weaver/api/test/getWeaverTestData`
  - JSON: `account` = 현재 Google 계정 이메일
- HTTP 성공 및 응답 `code` 0을 모두 확인한다. `code` 9는 실패로 처리하며, `DATA`에서 백업을 읽는다.
- 계정의 기존 서버 백업을 덮어쓸 때와 현재 기기 데이터를 덮어쓸 때 각각 확인한다.

`weaver.backup` 버전 1은 작업공간(JSON 버전 1), 캔버스 배치, 테마, 닫힌 생각 조회 설정, 사진·음성 파일의 Base64 문자열을 포함한다. 위치는 생각 메타데이터로 포함된다. 휴지통도 포함한다. 임시 백업 크기는 64MB로 제한하고, 파일 누락은 실패 처리한다. Base64는 암호화가 아니며 용량이 약 33% 늘어난다. 운영용으로는 별도 파일 업로드와 동작별 증분 API가 필요하다.

가져오기는 전체 데이터 검증 → 새 ID로 파일 임시 저장 → 기존 로컬 값을 `weaver.workspace.v1.beforeImport`에 보관 → 저장 교체 순서이다. 파일 임시 저장 실패 시 현재 파일을 덮어쓰지 않는다. 로컬 설정 교체 실패 시 기존 값을 복구한다. 이전 백업의 첨부파일은 유지한다. 오래된 사진·음성 없는 단독 작업공간 JSON도 허용한다.

생각 삭제는 휴지통 이동이다. 일반 목록·검색·어시스트의 데이터 집합에서 분리하며 첨부파일을 지우지 않는다. 휴지통에서 영구 삭제를 확인하면 로컬 저장 반영 후 더 이상 참조되지 않는 첨부파일을 지운다. 파일 삭제가 중단되면 `weaver.pendingMediaDeletion.v1` 큐를 다음 앱 실행에서 다시 처리한다. 서버의 이전 백업은 별도로 유지된다.

## 서버 확인 사항

웹에서 JSON POST를 받으려면 `https://dogpoo-net.github.io`의 CORS OPTIONS 요청과 `Content-Type` 헤더를 허용해야 한다. 요청 본문/DB 컬럼 크기는 첨부파일이 포함된 JSON을 수용해야 한다.

현재 제공된 계약은 이메일만 전달한다. 이메일은 인증 수단이 아니므로 서버가 이 값만 신뢰하면 다른 계정 데이터에 접근할 수 있다. 운영 전 Google ID 토큰 검증 및 계정 소유권 확인을 추가해야 한다. 클라이언트 비밀키를 앱에 넣지 않는다.

작업 환경 프록시가 `api.dogpoo.net` 접속을 차단해 실제 서버 응답/CORS는 검증하지 못했다. 모의 HTTP 테스트로 요청 JSON, 응답 코드, 실패 처리, 파일 포함 복원을 검증한다.

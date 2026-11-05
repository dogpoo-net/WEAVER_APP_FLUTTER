# 어시스트 안정 기준점

사용자가 한글 입력 동작을 확인하고 유지하도록 요청한 기준입니다.

- 원격 태그: `assist-stable-2026-11-05`
- 커밋: `c7f10d5`
- 현재 작업의 `caret_assist.dart`, `word_badge.dart`, `element_binding.dart`는 이 기준과 동일함을 확인한 후 100% 일치 자동 선택을 추가했습니다.

유지할 동작:

- 한글 조합 중 Ctrl 키다운에서 실제 입력 연결을 잠깐 해제하고 같은 입력폼으로 복원합니다. 본문과 커서 위치를 유지합니다.
- Ctrl만으로는 후보를 선택하지 않습니다. 이어지는 Space로 선택 조작에 진입합니다.
- Ctrl+Space 재입력은 수동 선택을 해제합니다. Esc는 선택 해제 후 어시스트 닫기로 동작합니다.
- 원소·태그를 선택한 Enter를 메모 저장에 중복 사용하지 않습니다.
- IME 조합 갱신이 명시적 선택·해제 상태를 덮어쓰지 않습니다.

전체 저장소를 이전 상태로 되돌리지 말고, 문제가 생긴 변경만 이 태그와 비교하여 복원합니다. 빠른 메모 배치, 프로젝트, 페이지 등 이후 작업을 덮어쓰지 않습니다.

관련 파일은 `lib/features/inbox/caret_assist.dart`, `inbox_page.dart`, `word_badge.dart`, `element_binding.dart`와 `test/assist_composition_toggle_test.dart`, `quick_assist_priority_test.dart`, `tag_assist_test.dart`, `desktop_assist_test.dart`입니다.

새 변경은 100% 일치하는 생각을 자동 선택하는 조건에 한정합니다. 부분 일치나 초성·조합 중 유사 일치만으로 자동 선택하지 않습니다. 자동 선택만으로 본문 변경, 연결 생성, 저장 또는 IME 조합 종료를 하지 않습니다.

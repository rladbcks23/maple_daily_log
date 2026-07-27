# 메이플 숙제알리미 앱

Flutter 데스크톱 앱 초안입니다. 현재 단계는 서버 API와 런처 감지 기능을 붙이기 전, 앱의 기본 화면 구조를 잡는 단계입니다.

## 현재 포함된 화면

- 오늘 알림 대시보드
- 선택 캐릭터 목록
- 일간/주간/보스 숙제 상태
- 공지/이벤트 새 글 알림
- 런처 종료 후 미완료 항목 알림 미리보기

## 실행 준비

Flutter SDK 설치 후 `app` 폴더에서 아래 명령을 실행하면 됩니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\run_windows.ps1
```

Flutter Windows 디버그 실행 중 접근성 엔진 로그가 PowerShell에 반복 출력될 수 있어,
기본 실행 스크립트는 해당 stderr 로그를 `.dart_tool/flutter_windows_stderr.log`에 저장합니다.
엔진 로그를 터미널에서 직접 보고 싶다면 `-ShowEngineLogs` 옵션을 붙이면 됩니다.

서버 연동 주소는 이후 앱 설정 또는 환경 파일로 분리할 예정입니다.

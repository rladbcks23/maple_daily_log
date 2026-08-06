# 메이플 숙제알리미 앱

메이플스토리 숙제/보스/공지 알림을 챙겨주는 Windows 데스크톱 앱 (Flutter)입니다.
사용법과 화면 설명은 저장소 루트의 [README.md](../README.md)를 참고하세요. 이 문서는 개발 환경 기준입니다.

## 개발 모드 실행

Flutter SDK 설치 후 `app` 폴더에서 아래 명령을 실행하면 됩니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\run_windows.ps1
```

Flutter Windows 디버그 실행 중 접근성 엔진 로그가 PowerShell에 반복 출력될 수 있어,
기본 실행 스크립트는 해당 stderr 로그를 `.dart_tool/flutter_windows_stderr.log`에 저장합니다.
엔진 로그를 터미널에서 직접 보고 싶다면 `-ShowEngineLogs` 옵션을 붙이면 됩니다.

서버 연동 주소는 앱 설정(넥슨 OpenAPI 키 입력 화면 하단) 또는 `AppConfig`에서 관리합니다.
기본값은 `app/lib/api_client.dart`의 `defaultApiBaseUrl`입니다.

## 배포용 빌드 만들기

정식 릴리스(zip/설치 프로그램)나 Shorebird 핫픽스 패치는 [app/installer/README.md](installer/README.md)를 참고하세요.

## 코드 구조 참고

- `lib/main.dart`: 앱 셸, 화면 라우팅, 알림 판단 로직 대부분이 여기 있습니다 (파일이 큽니다).
- `lib/api_client.dart`: 서버 API 호출 클라이언트.
- `lib/*_cache.dart`, `lib/*_store.dart`, `lib/notification_*.dart`: PC 로컬 캐시/설정 저장소. 저장 기준은 [docs/데이터 저장 기준.md](../docs/데이터%20저장%20기준.md) 참고.
- `windows/`: Flutter Windows 데스크톱 런너(네이티브 트레이 아이콘, 창 제어 등).

# Windows 배포

## 배포 파일 만들기

실행 중인 Flutter 디버그 앱을 먼저 종료한 뒤 `app` 폴더에서 다음 명령을 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\build_windows_release.ps1
```

스크립트는 의존성 확인, 정적 분석, 테스트, Windows 릴리스 빌드를 순서대로 실행합니다.
버전은 스크립트가 `pubspec.yaml`의 `version:` 값을 직접 읽어서 사용하므로 따로 맞춰줄 필요는 없습니다
(단, `app/installer/maple_task_reminder.iss`의 `MyAppVersion`/`MyDistVersion`과
`app/lib/main.dart`의 `appCurrentVersion` 상수는 릴리스 전에 함께 갱신해야 합니다).

완료된 파일은 저장소의 `dist` 폴더에 생성됩니다.

- `MapleTaskReminder-<버전>-windows-x64.zip`: 압축을 풀고 바로 실행하는 휴대용 배포본
- `MapleTaskReminder-Setup-<버전>.exe`: Windows 설치 프로그램

Inno Setup 6가 설치되어 있지 않으면 휴대용 ZIP만 생성됩니다.

기본적으로 이 빌드는 [Shorebird](https://shorebird.dev)로 만들어져서, 이후 순수 Dart 코드 버그는
재배포 없이 핫픽스 패치로 반영할 수 있습니다 (아래 "핫픽스 패치" 참고).

## 설치 프로그램 만들기

[Inno Setup 6](https://jrsoftware.org/isdl.php)을 개발 PC에 설치한 뒤 배포 스크립트를 다시 실행합니다.
설치 프로그램은 현재 사용자 영역에 앱을 설치하므로 관리자 권한이 필요하지 않습니다.

## 집 PC에서 사용하기

설치 프로그램을 실행하거나 휴대용 ZIP을 원하는 폴더에 모두 압축 해제한 뒤
`maple_task_reminder.exe`를 실행합니다. 집 PC에는 Flutter와 Visual Studio가 필요하지 않습니다.

캐릭터 선택과 스케줄러 캐시는 PC별로 새로 생성됩니다. API 조회를 위해 인터넷 연결과
Render 서버가 필요합니다.

서명되지 않은 개인 배포본이므로 Windows SmartScreen 경고가 표시될 수 있습니다.

## 핫픽스 패치 (Shorebird)

새 기능이나 네이티브/에셋 변경 없이, 순수 Dart 코드 버그만 고쳤을 때는 재설치 없이 패치를 보낼 수 있습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\shorebird_patch_windows.ps1
```

이미 설치된 앱(단, 위 방식대로 Shorebird로 빌드된 버전부터)이 다음 실행 시 백그라운드에서 자동으로 패치를 받습니다.
버전을 새로 올리거나 zip/설치 프로그램을 다시 만들 필요가 없습니다.

주의: 패치는 Dart 코드 변경만 담을 수 있습니다. 새 패키지 추가, 에셋 변경, 네이티브 코드 변경이 있으면
패치가 거부되며, 이 경우 위 "배포 파일 만들기"로 정식 릴리스를 다시 만들어야 합니다.

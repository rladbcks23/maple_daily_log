# 메이플 숙제알리미 Server

메이플 숙제알리미는 메이플스토리의 일일/주간 숙제, 이벤트, 공지사항을 확인해 사용자가 놓친 항목을 알려주는 알림 앱이다.
이 서버는 Nexon OpenAPI에서 필요한 정보를 수집하고, 앱이 알림을 판단할 수 있는 데이터를 제공한다.

## 현재 방향

- 서버와 앱을 분리해서 개발한다.
- 최우선 기능은 숙제, 이벤트, 공지 알림이다.
- 정보 조회, 성장 리포트, 장비 비교, 데이터 계산 기능은 만들지 않는다.
- 추가 기능은 알림 기능을 먼저 만든 뒤 필요하면 다시 검토한다.
- 알림은 데스크톱 기본 알림이 아니라, 백그라운드 실행 중인 앱이 화면에 켜지는 방식으로 제공한다.

## 서버 역할

- Nexon OpenAPI 호출
- 스케줄러 진행 상태 수집
- 일일/주간/보스 콘텐츠 완료 여부 정리
- 공지사항, 이벤트, 캐시샵 공지, 업데이트 목록 수집
- 앱이 알림을 띄울 수 있도록 미완료 항목과 새 공지 정보를 제공

## 앱 역할

- 백그라운드 실행
- 메이플 런처 종료 감지
- 서버에서 수집한 정보를 기반으로 알림 표시
- 오늘 접속하지 않았거나 일일 콘텐츠가 남아 있으면 알림
- 이번 주에 하지 않은 보스, 퀘스트, 이벤트가 있으면 알림
- 등록된 일일 이벤트를 모두 완료했다면 알림 생략

## 주요 사용 API

- `/maplestory/v1/scheduler/character-state`
- `/maplestory/v1/notice`
- `/maplestory/v1/notice/detail`
- `/maplestory/v1/notice-event`
- `/maplestory/v1/notice-event/detail`
- `/maplestory/v1/notice-cashshop`
- `/maplestory/v1/notice-cashshop/detail`
- `/maplestory/v1/notice-update`
- `/maplestory/v1/notice-update/detail`

## 실행

```powershell
cd server
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

## 관련 문서

- `기획/새 기획 정리.txt`
- `docs/사용 API 목록.md`

# 메이플 숙제알리미 Server

메이플 숙제알리미는 메이플스토리의 일일/주간 숙제, 이벤트, 공지사항을 확인해 사용자가 놓친 항목을 알려주는 알림 앱이다.
이 서버는 Nexon OpenAPI에서 필요한 정보를 수집하고, 앱이 알림 여부를 판단할 수 있는 데이터를 제공한다.

## 현재 기획 방향

- 서버와 앱을 분리해서 개발한다.
- 서비스의 핵심은 정보 조회가 아니라 놓친 숙제와 이벤트 알림이다.
- 알림은 데스크톱 기본 알림이 아니라, 백그라운드 실행 중인 앱이 화면에 켜지는 방식으로 제공한다.
- 1차 범위는 스케줄러 API와 공지 API를 활용한 알림 기능이다.
- 성장 리포트, 장비 비교, 상세 스냅샷 분석 기능은 현재 새 기획의 1차 범위에서 제외한다.

## 서버 역할

- Nexon OpenAPI 호출
- 스케줄러 진행 상태 수집
- 일일/주간/보스 콘텐츠 완료 여부 정리
- 공지사항, 이벤트, 캐시샵 공지, 업데이트 목록 수집
- 앱이 알림을 띄울 수 있도록 미완료 항목과 새 공지 정보를 제공
- API 호출 제한을 고려한 수집 주기 관리

## 앱 역할

- 백그라운드 실행
- 메이플 런처 종료 감지
- 서버에서 수집한 정보를 기반으로 알림 표시
- 오늘 접속하지 않았거나 일일 콘텐츠가 남아 있으면 알림
- 이번 주에 하지 않은 보스, 퀘스트, 이벤트가 있으면 알림
- 등록된 일일 이벤트를 모두 완료했다면 알림 생략

## 주요 사용 API

### 스케줄러

- `/maplestory/v1/scheduler/character-state`

사용 정보:

- 조회 기준일
- 캐릭터명, 월드명, 레벨, 직업
- 일일 콘텐츠 정보
- 주간 콘텐츠 정보
- 보스 콘텐츠 정보
- 주간 보스 처치 완료 횟수
- 주간 보스 처치 제한 횟수

### 공지

목록 조회:

- `/maplestory/v1/notice`
- `/maplestory/v1/notice-event`
- `/maplestory/v1/notice-cashshop`
- `/maplestory/v1/notice-update`

상세 조회:

- `/maplestory/v1/notice/detail`
- `/maplestory/v1/notice-event/detail`
- `/maplestory/v1/notice-cashshop/detail`
- `/maplestory/v1/notice-update/detail`

## 현재 서버 상태

기존 구현에는 캐릭터, 스냅샷, 플레이 세션, 리포트 관련 API가 포함되어 있다.
다만 새 기획에서는 알림 기능이 우선이므로, 이후 구현은 스케줄러/공지 기반 알림 흐름에 맞춰 재정리할 예정이다.

현재 구현된 주요 API:

- `GET /health`
- `GET /api/meta/nexon-endpoints`
- `GET /api/meta/snapshot-bundles`
- `GET /api/characters`
- `POST /api/characters`
- `PATCH /api/characters/{id}/tags`
- `POST /api/sync/characters`
- `POST /api/sync/snapshot`
- `POST /api/sync/snapshots`
- `POST /api/snapshots`
- `GET /api/snapshots/latest?character_id=...`
- `POST /api/play-sessions/start`
- `POST /api/play-sessions/{id}/end`
- `POST /api/reports/daily`
- `POST /api/reports/weekly`
- `POST /api/reports/monthly`
- `GET /api/reports`
- `GET /api/scheduler/missing-tasks?character_id=...&play_date=YYYY-MM-DD`

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
- `docs/API 호출 정책.md`

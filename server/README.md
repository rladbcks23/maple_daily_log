# Maple Daily Log Server

문서 기준으로 다시 만든 Django REST 서버다.

## 역할

- 캐릭터 기본 정보 저장
- 게임 시작/종료 이벤트 저장
- 플레이 세션과 총 플레이타임 기록
- Nexon API 스냅샷 저장
- 일일/주간/월간 리포트 생성
- 스케줄러 미완료 항목 확인용 데이터 제공

## 실행

```powershell
cd server
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

## 주요 API

- `GET /health`
- `GET /api/meta/nexon-endpoints`
- `GET /api/meta/snapshot-bundles`
- `GET /api/characters`
- `POST /api/characters`
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

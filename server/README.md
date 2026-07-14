# 메이플 숙제알리미 Server

DRF + SQLite 기반 API 서버다.
서버는 Nexon OpenAPI 호출, 선택 캐릭터 저장, 공지 목록 비교, 알림 판단 결과 생성을 담당한다.

## 네가 채워야 하는 값

`server/.env.example`을 복사해 `server/.env`를 만들고 아래 값을 채운다.

```powershell
copy server\.env.example server\.env
```

필수:

- `NEXON_API_KEY`: Nexon OpenAPI key

선택:

- `DJANGO_SECRET_KEY`: 운영용 비밀키
- `DJANGO_DEBUG`: 개발 중에는 `true`
- `DJANGO_ALLOWED_HOSTS`: 허용할 호스트 목록
- `NEXON_API_TIMEOUT_SECONDS`: Nexon API 요청 제한 시간

## 실행

```powershell
cd server
.\.venv\Scripts\Activate.ps1
python manage.py migrate
python manage.py runserver
```

## 주요 API

상태:

- `GET /health`

선택 캐릭터:

- `GET /api/selected-characters/`
- `POST /api/selected-characters/`
- `GET /api/selected-characters/{id}/`
- `PATCH /api/selected-characters/{id}/`
- `DELETE /api/selected-characters/{id}/`
- `POST /api/selected-characters/{id}/refresh/`

Nexon API 프록시:

- `GET /api/nexon/characters`
- `GET /api/nexon/ocid?character_name=...`
- `GET /api/nexon/characters/{ocid}/basic`
- `GET /api/nexon/scheduler/{ocid}`

공지:

- `GET /api/notices/current`
- `POST /api/notices/check-new`
- `GET /api/notice-snapshots/`

알림 판단:

- `POST /api/reminders/daily-check`
- `POST /api/reminders/weekly-check`
- `POST /api/reminders/launcher-exit-check`

`weekly-check`는 기본적으로 화요일/수요일에만 판단한다.
테스트나 수동 확인이 필요하면 요청 바디에 `"force": true`를 넣는다.

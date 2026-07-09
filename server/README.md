# Maple Daily Log Server

Django REST Framework server for collecting Nexon OpenAPI data, saving local SQLite records, and triggering report jobs.

The server owns Nexon API calls, writes, force refresh, and report calculation. The app should read data from this server API instead of connecting to Supabase directly.

## Environment

Required environment variables:

- `ADMIN_TOKEN`
- `NEXON_API_KEY`
- `DJANGO_SECRET_KEY`

Optional:

- `DJANGO_DEBUG=false`
- `DJANGO_ALLOWED_HOSTS=*`
- `SQLITE_PATH=db.sqlite3`
- `NEXON_API_BASE_URL=https://open.api.nexon.com`
- `NEXON_REQUESTS_PER_SECOND=5`
- `NEXON_REQUESTS_PER_DAY=1000`
- `MAPLE_TIMEZONE=Asia/Seoul`

Local runs automatically load `server/.env`.

## Local Run

```text
pip install -r requirements.txt
python manage.py runserver
```

Do not run `python manage.py migrate` for the Maple app tables right now. The server creates the SQLite tables it needs when the API is called.

All endpoints except `/health` require:

```text
Authorization: Bearer <ADMIN_TOKEN>
```

## API Surface

- `GET /health`
- `GET /api/characters`
- `GET /api/characters/<character_id>/latest-snapshot`
- `POST /api/sync/characters`
- `POST /api/sync/snapshot`
- `POST /api/reports/daily`

`POST /api/sync/characters` calls Nexon OpenAPI account character list and upserts every returned character into `characters`.

`POST /api/sync/snapshot` calls Nexon OpenAPI, upserts the character row, and saves the response bundle into `character_snapshots.snapshot_json`.

Snapshot sync accepts any one of these identifiers:

- `ocid`
- `characterId`
- `characterName`

## Database

The default SQLite database file is:

- `server/db.sqlite3`

You can change it with:

```text
SQLITE_PATH=<path-to-sqlite-file>
```

The reference schema is:

- `../database/schema.sql`

The first version stores most character state in `character_snapshots.snapshot_json`.

Nexon API request budget notes are in:

- `../docs/nexon-api-rules.md`

## App Data Flow

The app should call the DRF server read APIs:

- `GET /api/characters`
- `GET /api/characters/<character_id>/latest-snapshot`

Do not put the Nexon API key or admin token in a public app build. For a personal local app, keep them only in `server/.env`.

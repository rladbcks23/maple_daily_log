# Maple Daily Log Server

Django REST Framework server for collecting Nexon OpenAPI data, saving snapshots to Supabase PostgreSQL, and triggering report jobs.

The Flutter app still reads data directly from Supabase with read-only RLS policies.
The DRF server owns writes, Nexon API calls, force refresh, and report calculation.

## Environment

Required environment variables:

- `DATABASE_URL`
- `DATABASE_USERNAME`
- `DATABASE_PASSWORD`
- `ADMIN_TOKEN`
- `NEXON_API_KEY`
- `DJANGO_SECRET_KEY`

Optional:

- `DJANGO_DEBUG=false`
- `DJANGO_ALLOWED_HOSTS=*`
- `DATABASE_SSLMODE=require`
- `NEXON_API_BASE_URL=https://open.api.nexon.com`
- `NEXON_REQUESTS_PER_SECOND=5`
- `NEXON_REQUESTS_PER_DAY=1000`
- `MAPLE_TIMEZONE=Asia/Seoul`

## Local Run

```text
pip install -r requirements.txt
python manage.py runserver
```

Local runs automatically load `server/.env`.

Pooler example:

```text
DATABASE_URL=postgresql://aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres
DATABASE_USERNAME=postgres.<project-ref>
DATABASE_PASSWORD=<database-password>
DATABASE_SSLMODE=require
```

Keep `DATABASE_PASSWORD` separate from `DATABASE_URL`, especially when the password contains special characters such as `@`.

Do not run `python manage.py migrate` for this project right now.

This server does not use Django models for the app tables. Supabase tables are created from:

- `../database/schema.sql`
- `../database/rls.sql`

All endpoints except `/health` require:

```text
Authorization: Bearer <ADMIN_TOKEN>
```

## API Surface

- `GET /health`
- `POST /api/sync/characters`
- `POST /api/sync/snapshot`
- `POST /api/reports/daily`

`POST /api/sync/characters` calls Nexon OpenAPI account character list and upserts every returned character into `characters`.

`POST /api/sync/snapshot` calls Nexon OpenAPI, upserts the character row, and saves the response bundle into `character_snapshots.snapshot_json`.

## Database

The Supabase SQL files are outside the server:

- `../database/schema.sql`
- `../database/rls.sql`

The first version stores most character state in `character_snapshots.snapshot_json`.

Nexon API request budget notes are in:

- `../docs/nexon-api-rules.md`

## App Data Flow

Flutter reads these tables directly from Supabase:

- `characters`
- `character_snapshots`
- `starforce_events`
- `cube_events`
- `potential_events`
- `play_time_records`
- `reports`

The app should use the Supabase anon key only. Do not put the Nexon API key, admin token, database password, or Supabase service role key in the app.

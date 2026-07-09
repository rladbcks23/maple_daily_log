# Maple Daily Log Server

Spring Boot server for collecting Nexon OpenAPI data, saving snapshots to Supabase, and creating reports.

The Flutter app reads data directly from Supabase with read-only RLS policies.
The server owns writes, Nexon API calls, manual refresh triggers, and report calculation.

## Environment

Required environment variables:

- `DATABASE_URL`
- `DATABASE_USERNAME`
- `DATABASE_PASSWORD`
- `ADMIN_TOKEN`
- `NEXON_API_KEY`

Optional:

- `FLYWAY_ENABLED=true`
- `NEXON_API_BASE_URL=https://open.api.nexon.com`
- `NEXON_REQUESTS_PER_SECOND=5`
- `NEXON_REQUESTS_PER_DAY=1000`

## First API Surface

- `GET /health`
- `POST /api/sync/characters`
- `POST /api/sync/snapshot`
- `POST /api/reports/daily`

All endpoints except `/health` require:

```text
Authorization: Bearer <ADMIN_TOKEN>
```

## Database

The Supabase schema is in:

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

The app only calls this server for actions such as:

- force refresh
- daily report calculation trigger

## Nexon API Client

`POST /api/sync/characters` calls Nexon OpenAPI account character list and upserts every returned character into `characters`.

`POST /api/sync/snapshot` calls Nexon OpenAPI, upserts the character row, and saves the response bundle into `character_snapshots.snapshot_json`.

If the database was created before `force_refresh` was added as a snapshot type, run:

- `src/main/resources/db/migration/V2__add_force_refresh_snapshot_type.sql`

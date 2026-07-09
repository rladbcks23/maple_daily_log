# Maple Daily Log Server

Spring Boot server for collecting Nexon OpenAPI data, saving snapshots to Supabase, and creating reports.

## Environment

Required environment variables:

- `DATABASE_URL`
- `DATABASE_USERNAME`
- `DATABASE_PASSWORD`
- `ADMIN_TOKEN`
- `NEXON_API_KEY`

Optional:

- `FLYWAY_ENABLED=true`

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

The first version stores most character state in `character_snapshots.snapshot_json`.

# Nexon API Rules

## Rate Limit

Current planning limit:

- `5 requests / second`
- `1,000 requests / day`

The server must treat these values as a request budget.

The default values are configured in `server/src/main/resources/application.yml`:

- `maple.nexon-rate-limit.requests-per-second`
- `maple.nexon-rate-limit.requests-per-day`

## Design Impact

The first version should avoid scanning every character with every endpoint on every refresh.

Recommended behavior:

- Collect full snapshots only for important characters.
- Synchronize the account character list first, then choose characters from the saved `characters` table.
- Use character tags to reduce collection scope.
- Use force refresh for the currently selected or explicitly requested character.
- Skip ignored/storage characters.
- Prefer one snapshot bundle per trigger instead of repeated polling while the game is running.

## Character Collection Scope

Newly synchronized characters start with the `ignored` tag by default.

This keeps new account characters out of automatic collection until the user explicitly classifies them.

Current policy:

- Default tag: `ignored`
- Automatic/bulk collection excludes:
  - characters with `is_ignored = true`
  - characters tagged `ignored`
  - characters tagged `storage`
- Tag-specific collection intervals are deferred until the app workflow is clearer.
- For now, broad scheduled collection should target every non-ignored character only.

## Trigger Policy

Recommended API trigger points:

- app start: lightweight sync and missing report check
- game start: pre-play snapshot for active characters
- game end: final snapshot and event logs
- force refresh: snapshot for the selected character
- scheduled settlement: report creation and missing data check

## Snapshot Budget

Each snapshot may call multiple Nexon endpoints.

For this reason, `POST /api/sync/snapshot` returns how many Nexon API calls were used.

Example response shape:

```json
{
  "status": "saved",
  "ocid": "example",
  "snapshotId": "uuid",
  "apiCallsUsed": 8
}
```

## Future Guardrails

Before implementing broad sync jobs, add:

- daily request counter
- per-second throttle
- endpoint retry policy
- clear error when the daily budget is exhausted

# Report Rules

## Daily Report

Daily reports compare the previous play day's last snapshot with the report day's last snapshot.

Example:

- `2026-07-08` last snapshot
- `2026-07-09` last snapshot
- `2026-07-09` daily report = difference between those two snapshots

## Snapshot Selection

For each character and report date:

1. `end_snapshot` is the latest `character_snapshots` row for the report date.
2. `start_snapshot` is the latest `character_snapshots` row before the report date.
3. The report stores both `start_snapshot_id` and `end_snapshot_id`.
4. If there is no `start_snapshot`, create the report as the first baseline report.
5. If there is no `end_snapshot`, do not create a daily report for that character/date.

## Play Date Rule

`recorded_at` is the real timestamp when the snapshot was saved.

`play_date` is the date the play session belongs to.

If a game session starts before midnight and ends after midnight, the session belongs to the date when the game started.

Example:

- Start: `2026-07-09 23:30 KST`
- End: `2026-07-10 02:00 KST`
- `play_date`: `2026-07-09`
- `recorded_at`: actual saved time, such as `2026-07-10 02:00 KST`

## Play Time

Play time is stored as total minutes.

Examples:

- `210` means `3 hours 30 minutes`
- `75` means `1 hour 15 minutes`

The app is responsible for formatting minutes into user-facing text.

## Snapshot JSON

The first version stores most API data in `character_snapshots.snapshot_json`.

Frequently compared values may also be copied into columns for easier querying:

- `character_level`
- `character_exp`
- `exp_rate`
- `combat_power`

Equipment, symbols, Hexa, ability, hyper stat, and detailed stats stay inside `snapshot_json` for now.

## Report JSON

`reports.summary_json` stores the calculated result shown in the app.

Expected sections:

- `level`
- `experience`
- `combat_power`
- `equipment`
- `symbols`
- `hexa`
- `starforce`
- `cube`
- `potential`
- `play_time`
- `accuracy_labels`

## Accuracy Labels

Use these labels when report values are shown:

- `API_REPORTED`: direct API data or API log
- `SNAPSHOT_DIFF`: difference between two snapshots
- `RULE_CALCULATED`: calculated from official rules or cost tables
- `ESTIMATED`: inferred value
- `MANUAL`: manually entered by the user

alter table character_snapshots
    drop constraint if exists character_snapshots_snapshot_type_check;

alter table character_snapshots
    add constraint character_snapshots_snapshot_type_check
        check (snapshot_type in ('app_start', 'game_start', 'game_end', 'force_refresh', 'manual', 'scheduled'));

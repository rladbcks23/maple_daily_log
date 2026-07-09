pragma foreign_keys = on;

create table if not exists characters (
    id text primary key,
    ocid text not null unique,
    character_name text not null,
    world_name text,
    character_class text,
    character_class_level text,
    character_level integer,
    tags text not null default '[]',
    is_ignored integer not null default 0,
    last_synced_at text,
    created_at text not null default (datetime('now')),
    updated_at text not null default (datetime('now'))
);

create table if not exists character_snapshots (
    id text primary key,
    character_id text not null references characters(id) on delete cascade,
    snapshot_type text not null default 'manual',
    play_date text not null,
    recorded_at text not null default (datetime('now')),
    character_level integer,
    exp_rate text,
    combat_power text,
    snapshot_json text not null,
    created_at text not null default (datetime('now')),
    check (snapshot_type in ('app_start', 'game_start', 'game_end', 'force_refresh', 'manual', 'scheduled'))
);

create table if not exists starforce_events (
    id text primary key,
    character_id text references characters(id) on delete set null,
    event_date text not null,
    event_at text,
    item_name text,
    before_star integer,
    after_star integer,
    result text,
    raw_json text not null,
    created_at text not null default (datetime('now'))
);

create table if not exists cube_events (
    id text primary key,
    character_id text references characters(id) on delete set null,
    event_date text not null,
    event_at text,
    cube_type text,
    item_name text,
    before_potential text,
    after_potential text,
    raw_json text not null,
    created_at text not null default (datetime('now'))
);

create table if not exists potential_events (
    id text primary key,
    character_id text references characters(id) on delete set null,
    event_date text not null,
    event_at text,
    reset_type text,
    item_name text,
    before_grade text,
    after_grade text,
    raw_json text not null,
    created_at text not null default (datetime('now'))
);

create table if not exists play_time_records (
    id text primary key,
    character_id text references characters(id) on delete set null,
    play_date text not null,
    play_minutes integer not null default 0,
    source text not null default 'local_app',
    started_at text,
    ended_at text,
    note text,
    created_at text not null default (datetime('now')),
    updated_at text not null default (datetime('now')),
    check (source in ('local_app', 'manual', 'estimated')),
    check (play_minutes >= 0)
);

create table if not exists reports (
    id text primary key,
    character_id text references characters(id) on delete set null,
    report_type text not null,
    report_date text not null,
    start_snapshot_id text references character_snapshots(id) on delete set null,
    end_snapshot_id text references character_snapshots(id) on delete set null,
    play_minutes integer not null default 0,
    level_delta integer,
    exp_delta text,
    combat_power_delta text,
    summary_json text not null,
    created_at text not null default (datetime('now')),
    updated_at text not null default (datetime('now')),
    check (report_type in ('daily', 'weekly', 'monthly')),
    check (play_minutes >= 0),
    unique (character_id, report_type, report_date)
);

create index if not exists idx_characters_name
    on characters(character_name);

create index if not exists idx_character_snapshots_character_date
    on character_snapshots(character_id, play_date, recorded_at desc);

create index if not exists idx_starforce_events_character_date
    on starforce_events(character_id, event_date);

create index if not exists idx_cube_events_character_date
    on cube_events(character_id, event_date);

create index if not exists idx_potential_events_character_date
    on potential_events(character_id, event_date);

create index if not exists idx_play_time_records_character_date
    on play_time_records(character_id, play_date);

create index if not exists idx_reports_character_period
    on reports(character_id, report_type, report_date desc);

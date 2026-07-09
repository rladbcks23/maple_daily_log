create extension if not exists pgcrypto;

create table if not exists characters (
    id uuid primary key default gen_random_uuid(),
    ocid text not null unique,
    character_name text not null,
    world_name text,
    character_class text,
    character_class_level text,
    character_level integer,
    tags text[] not null default '{}',
    is_ignored boolean not null default false,
    last_synced_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists character_snapshots (
    id uuid primary key default gen_random_uuid(),
    character_id uuid not null references characters(id) on delete cascade,
    snapshot_type text not null default 'manual',
    play_date date not null,
    recorded_at timestamptz not null default now(),
    character_level integer,
    exp_rate numeric(8, 5),
    combat_power numeric(24, 0),
    snapshot_json jsonb not null,
    created_at timestamptz not null default now(),
    constraint character_snapshots_snapshot_type_check
        check (snapshot_type in ('app_start', 'game_start', 'game_end', 'manual', 'scheduled'))
);

create table if not exists starforce_events (
    id uuid primary key default gen_random_uuid(),
    character_id uuid references characters(id) on delete set null,
    event_date date not null,
    event_at timestamptz,
    item_name text,
    before_star integer,
    after_star integer,
    result text,
    raw_json jsonb not null,
    created_at timestamptz not null default now()
);

create table if not exists cube_events (
    id uuid primary key default gen_random_uuid(),
    character_id uuid references characters(id) on delete set null,
    event_date date not null,
    event_at timestamptz,
    cube_type text,
    item_name text,
    before_potential text,
    after_potential text,
    raw_json jsonb not null,
    created_at timestamptz not null default now()
);

create table if not exists potential_events (
    id uuid primary key default gen_random_uuid(),
    character_id uuid references characters(id) on delete set null,
    event_date date not null,
    event_at timestamptz,
    reset_type text,
    item_name text,
    before_grade text,
    after_grade text,
    raw_json jsonb not null,
    created_at timestamptz not null default now()
);

create table if not exists play_time_records (
    id uuid primary key default gen_random_uuid(),
    character_id uuid references characters(id) on delete set null,
    play_date date not null,
    play_minutes integer not null default 0,
    source text not null default 'local_app',
    started_at timestamptz,
    ended_at timestamptz,
    note text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint play_time_records_source_check
        check (source in ('local_app', 'manual', 'estimated')),
    constraint play_time_records_minutes_check
        check (play_minutes >= 0)
);

create table if not exists reports (
    id uuid primary key default gen_random_uuid(),
    character_id uuid references characters(id) on delete set null,
    report_type text not null,
    report_date date not null,
    start_snapshot_id uuid references character_snapshots(id) on delete set null,
    end_snapshot_id uuid references character_snapshots(id) on delete set null,
    play_minutes integer not null default 0,
    level_delta integer,
    exp_delta numeric(18, 5),
    combat_power_delta numeric(24, 0),
    summary_json jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint reports_report_type_check
        check (report_type in ('daily', 'weekly', 'monthly')),
    constraint reports_play_minutes_check
        check (play_minutes >= 0),
    constraint reports_unique_period
        unique (character_id, report_type, report_date)
);

create index if not exists idx_characters_name
    on characters(character_name);

create index if not exists idx_character_snapshots_character_date
    on character_snapshots(character_id, play_date, recorded_at desc);

create index if not exists idx_character_snapshots_json
    on character_snapshots using gin(snapshot_json);

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

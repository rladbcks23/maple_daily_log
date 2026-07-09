import json
import uuid
from decimal import Decimal, InvalidOperation

from django.db import connection


def ensure_schema():
    with connection.cursor() as cursor:
        cursor.execute("pragma foreign_keys = on")
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute(
            """
            create table if not exists character_snapshots (
                id text primary key,
                character_id text not null references characters(id) on delete cascade,
                snapshot_type text not null default 'manual',
                play_date text not null,
                recorded_at text not null default (datetime('now')),
                character_level integer,
                character_exp text,
                exp_rate text,
                combat_power text,
                snapshot_json text not null,
                created_at text not null default (datetime('now')),
                check (snapshot_type in ('app_start', 'game_start', 'game_end', 'force_refresh', 'manual', 'scheduled'))
            )
            """
        )
        _add_column_if_missing(cursor, "character_snapshots", "character_exp", "text")
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute(
            """
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
            )
            """
        )
        cursor.execute("create index if not exists idx_characters_name on characters(character_name)")
        cursor.execute(
            """
            create index if not exists idx_character_snapshots_character_date
            on character_snapshots(character_id, play_date, recorded_at desc)
            """
        )
        cursor.execute("create index if not exists idx_starforce_events_character_date on starforce_events(character_id, event_date)")
        cursor.execute("create index if not exists idx_cube_events_character_date on cube_events(character_id, event_date)")
        cursor.execute("create index if not exists idx_potential_events_character_date on potential_events(character_id, event_date)")
        cursor.execute("create index if not exists idx_play_time_records_character_date on play_time_records(character_id, play_date)")
        cursor.execute("create index if not exists idx_reports_character_period on reports(character_id, report_type, report_date desc)")


def upsert_characters(characters):
    ensure_schema()

    saved = 0
    with connection.cursor() as cursor:
        for character in characters:
            ocid = character.get("ocid")
            if not ocid:
                continue

            character_id = _get_character_id(cursor, ocid) or str(uuid.uuid4())
            cursor.execute(
                """
                insert into characters (
                    id,
                    ocid,
                    character_name,
                    world_name,
                    character_class,
                    character_level,
                    last_synced_at,
                    updated_at
                )
                values (%s, %s, %s, %s, %s, %s, datetime('now'), datetime('now'))
                on conflict (ocid) do update set
                    character_name = excluded.character_name,
                    world_name = excluded.world_name,
                    character_class = excluded.character_class,
                    character_level = excluded.character_level,
                    last_synced_at = datetime('now'),
                    updated_at = datetime('now')
                """,
                [
                    character_id,
                    ocid,
                    character.get("character_name") or ocid,
                    character.get("world_name"),
                    character.get("character_class"),
                    character.get("character_level"),
                ],
            )
            saved += 1
    return saved


def save_snapshot(bundle, snapshot_type, play_date):
    ensure_schema()

    basic = bundle.sections.get("basic") or {}
    level = basic.get("character_level")
    character_exp = _number_text_or_none(basic.get("character_exp"))
    exp_rate = _decimal_or_none(basic.get("character_exp_rate"))
    combat_power = _combat_power(bundle.sections.get("stat") or {})
    character_id = None

    with connection.cursor() as cursor:
        existing_character_id = _get_character_id(cursor, bundle.ocid)
        character_id = existing_character_id or str(uuid.uuid4())
        cursor.execute(
            """
            insert into characters (
                id,
                ocid,
                character_name,
                world_name,
                character_class,
                character_class_level,
                character_level,
                last_synced_at,
                updated_at
            )
            values (%s, %s, %s, %s, %s, %s, %s, datetime('now'), datetime('now'))
            on conflict (ocid) do update set
                character_name = excluded.character_name,
                world_name = excluded.world_name,
                character_class = excluded.character_class,
                character_class_level = excluded.character_class_level,
                character_level = excluded.character_level,
                last_synced_at = datetime('now'),
                updated_at = datetime('now')
            """,
            [
                character_id,
                bundle.ocid,
                basic.get("character_name") or bundle.ocid,
                basic.get("world_name"),
                basic.get("character_class"),
                basic.get("character_class_level"),
                level,
            ],
        )
        character_id = _get_character_id(cursor, bundle.ocid)

        snapshot_json = {
            "ocid": bundle.ocid,
            "collectedAt": bundle.collected_at.isoformat(),
            "apiCallsUsed": bundle.api_calls_used,
            "sections": bundle.sections,
        }
        snapshot_id = str(uuid.uuid4())

        cursor.execute(
            """
            insert into character_snapshots (
                id,
                character_id,
                snapshot_type,
                play_date,
                recorded_at,
                character_level,
                character_exp,
                exp_rate,
                combat_power,
                snapshot_json
            )
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                snapshot_id,
                character_id,
                snapshot_type,
                play_date.isoformat(),
                bundle.collected_at.isoformat(),
                level,
                character_exp,
                _decimal_to_text(exp_rate),
                _decimal_to_text(combat_power),
                json.dumps(snapshot_json, ensure_ascii=False),
            ],
        )

    return {
        "characterId": str(character_id),
        "snapshotId": str(snapshot_id),
        "characterName": basic.get("character_name") or bundle.ocid,
        "characterLevel": level,
        "characterExp": character_exp,
        "expRate": _decimal_to_text(exp_rate),
        "playDate": play_date.isoformat(),
    }


def list_characters():
    ensure_schema()

    with connection.cursor() as cursor:
        cursor.execute(
            """
            select
                id,
                ocid,
                character_name,
                world_name,
                character_class,
                character_class_level,
                character_level,
                tags,
                is_ignored,
                last_synced_at,
                created_at,
                updated_at
            from characters
            order by is_ignored asc, world_name asc, character_name asc
            """
        )
        return [_character_row_to_dict(row) for row in cursor.fetchall()]


def find_character(identifier):
    ensure_schema()

    clauses = []
    params = []
    if identifier.get("characterId"):
        clauses.append("id = %s")
        params.append(identifier["characterId"])
    if identifier.get("ocid"):
        clauses.append("ocid = %s")
        params.append(identifier["ocid"])
    if identifier.get("characterName"):
        clauses.append("character_name = %s")
        params.append(identifier["characterName"])

    if not clauses:
        return None

    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            select
                id,
                ocid,
                character_name,
                world_name,
                character_class,
                character_class_level,
                character_level,
                tags,
                is_ignored,
                last_synced_at,
                created_at,
                updated_at
            from characters
            where {" or ".join(clauses)}
            order by is_ignored asc, last_synced_at desc
            limit 1
            """,
            params,
        )
        row = cursor.fetchone()

    return _character_row_to_dict(row) if row else None


def latest_snapshot(character_id):
    ensure_schema()

    with connection.cursor() as cursor:
        cursor.execute(
            """
            select
                id,
                character_id,
                snapshot_type,
                play_date,
                recorded_at,
                character_level,
                character_exp,
                exp_rate,
                combat_power,
                snapshot_json,
                created_at
            from character_snapshots
            where character_id = %s
            order by recorded_at desc
            limit 1
            """,
            [character_id],
        )
        row = cursor.fetchone()

    if not row:
        return None
    return _snapshot_row_to_dict(row)


def _get_character_id(cursor, ocid):
    cursor.execute("select id from characters where ocid = %s", [ocid])
    row = cursor.fetchone()
    return row[0] if row else None


def _character_row_to_dict(row):
    return {
        "id": row[0],
        "ocid": row[1],
        "characterName": row[2],
        "worldName": row[3],
        "characterClass": row[4],
        "characterClassLevel": row[5],
        "characterLevel": row[6],
        "tags": json.loads(row[7] or "[]"),
        "isIgnored": bool(row[8]),
        "lastSyncedAt": row[9],
        "createdAt": row[10],
        "updatedAt": row[11],
    }


def _snapshot_row_to_dict(row):
    return {
        "id": row[0],
        "characterId": row[1],
        "snapshotType": row[2],
        "playDate": row[3],
        "recordedAt": row[4],
        "characterLevel": row[5],
        "characterExp": row[6],
        "expRate": row[7],
        "combatPower": row[8],
        "snapshot": json.loads(row[9]),
        "createdAt": row[10],
    }


def _combat_power(stat):
    for final_stat in stat.get("final_stat") or []:
        if final_stat.get("stat_name") in ("전투력", "Combat Power"):
            return _decimal_or_none(final_stat.get("stat_value"))
    return None


def _decimal_or_none(value):
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value).replace(",", ""))
    except (InvalidOperation, ValueError):
        return None


def _decimal_to_text(value):
    return str(value) if value is not None else None


def _number_text_or_none(value):
    if value is None or value == "":
        return None
    return str(value).replace(",", "")


def _add_column_if_missing(cursor, table_name, column_name, column_type):
    cursor.execute(f"pragma table_info({table_name})")
    existing_columns = {row[1] for row in cursor.fetchall()}
    if column_name not in existing_columns:
        cursor.execute(f"alter table {table_name} add column {column_name} {column_type}")

import json
from decimal import Decimal, InvalidOperation

from django.db import connection


def upsert_characters(characters):
    saved = 0
    with connection.cursor() as cursor:
        for character in characters:
            ocid = character.get("ocid")
            if not ocid:
                continue

            cursor.execute(
                """
                insert into characters (
                    ocid,
                    character_name,
                    world_name,
                    character_class,
                    character_level,
                    last_synced_at,
                    updated_at
                )
                values (%s, %s, %s, %s, %s, now(), now())
                on conflict (ocid) do update set
                    character_name = excluded.character_name,
                    world_name = excluded.world_name,
                    character_class = excluded.character_class,
                    character_level = excluded.character_level,
                    last_synced_at = now(),
                    updated_at = now()
                """,
                [
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
    basic = bundle.sections.get("basic") or {}
    level = basic.get("character_level")
    exp_rate = _decimal_or_none(basic.get("character_exp_rate"))
    combat_power = _combat_power(bundle.sections.get("stat") or {})

    with connection.cursor() as cursor:
        cursor.execute(
            """
            insert into characters (
                ocid,
                character_name,
                world_name,
                character_class,
                character_class_level,
                character_level,
                last_synced_at,
                updated_at
            )
            values (%s, %s, %s, %s, %s, %s, now(), now())
            on conflict (ocid) do update set
                character_name = excluded.character_name,
                world_name = excluded.world_name,
                character_class = excluded.character_class,
                character_class_level = excluded.character_class_level,
                character_level = excluded.character_level,
                last_synced_at = now(),
                updated_at = now()
            returning id
            """,
            [
                bundle.ocid,
                basic.get("character_name") or bundle.ocid,
                basic.get("world_name"),
                basic.get("character_class"),
                basic.get("character_class_level"),
                level,
            ],
        )
        character_id = cursor.fetchone()[0]

        snapshot_json = {
            "ocid": bundle.ocid,
            "collectedAt": bundle.collected_at.isoformat(),
            "apiCallsUsed": bundle.api_calls_used,
            "sections": bundle.sections,
        }

        cursor.execute(
            """
            insert into character_snapshots (
                character_id,
                snapshot_type,
                play_date,
                recorded_at,
                character_level,
                exp_rate,
                combat_power,
                snapshot_json
            )
            values (%s, %s, %s, %s, %s, %s, %s, %s::jsonb)
            returning id
            """,
            [
                character_id,
                snapshot_type,
                play_date,
                bundle.collected_at,
                level,
                exp_rate,
                combat_power,
                json.dumps(snapshot_json, ensure_ascii=False),
            ],
        )
        snapshot_id = cursor.fetchone()[0]

    return {
        "characterId": str(character_id),
        "snapshotId": str(snapshot_id),
        "characterName": basic.get("character_name") or bundle.ocid,
        "characterLevel": level,
        "playDate": play_date.isoformat(),
    }


def _combat_power(stat):
    for final_stat in stat.get("final_stat") or []:
        if final_stat.get("stat_name") == "전투력":
            return _decimal_or_none(final_stat.get("stat_value"))
    return None


def _decimal_or_none(value):
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value).replace(",", ""))
    except (InvalidOperation, ValueError):
        return None

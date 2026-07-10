from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from django.db.models import Sum
from django.utils import timezone

from .models import Character, CharacterSnapshot, PlaySession, Report
from .nexon import NexonClient


def today_play_date() -> date:
    return timezone.localdate()


def minutes_between(started_at: datetime, ended_at: datetime) -> int:
    seconds = max(0, int((ended_at - started_at).total_seconds()))
    return seconds // 60


def start_play_session(
    *,
    character: Character | None,
    play_date: date,
    started_at: datetime | None = None,
    start_snapshot: CharacterSnapshot | None = None,
) -> PlaySession:
    return PlaySession.objects.create(
        character=character,
        play_date=play_date,
        started_at=started_at or timezone.now(),
        start_snapshot=start_snapshot,
    )


def sync_characters_from_nexon(client: NexonClient | None = None) -> dict[str, Any]:
    client = client or NexonClient()
    synced = []
    created_count = 0
    updated_count = 0

    for character_data in client.character_list():
        character, created = Character.objects.update_or_create(
            ocid=character_data["ocid"],
            defaults={
                "character_name": character_data["character_name"],
                "world_name": character_data.get("world_name", ""),
                "character_class": character_data.get("character_class", ""),
                "character_class_level": character_data.get("character_class_level", ""),
                "character_level": character_data.get("character_level"),
                "last_synced_at": timezone.now(),
            },
        )
        created_count += int(created)
        updated_count += int(not created)
        synced.append(character)

    return {
        "created": created_count,
        "updated": updated_count,
        "total": len(synced),
        "characters": synced,
    }


def sync_character_snapshot_from_nexon(
    *,
    character: Character,
    bundle_name: str,
    snapshot_type: str,
    play_date: date,
    client: NexonClient | None = None,
) -> dict[str, Any]:
    client = client or NexonClient()
    snapshot_json, api_calls_used = client.collect_bundle_with_count(
        bundle_name,
        params={"ocid": character.ocid},
    )
    extracted = extract_snapshot_columns(snapshot_json)

    snapshot = CharacterSnapshot.objects.create(
        character=character,
        snapshot_type=snapshot_type,
        bundle_name=bundle_name,
        play_date=play_date,
        character_level=extracted["character_level"],
        character_exp=extracted["character_exp"],
        exp_rate=extracted["exp_rate"],
        combat_power=extracted["combat_power"],
        snapshot_json=snapshot_json,
    )

    update_character_from_snapshot(character, snapshot_json)

    return {
        "snapshot": snapshot,
        "api_calls_used": api_calls_used,
        "bundle_name": bundle_name,
        "snapshot_type": snapshot_type,
    }


def extract_snapshot_columns(snapshot_json: dict[str, Any]) -> dict[str, Any]:
    basic = snapshot_json.get("character_basic") or {}
    stat = snapshot_json.get("character_stat") or {}
    return {
        "character_level": basic.get("character_level"),
        "character_exp": stringify_or_blank(basic.get("character_exp")),
        "exp_rate": stringify_or_blank(basic.get("character_exp_rate")),
        "combat_power": stringify_or_blank(extract_combat_power(stat)),
    }


def update_character_from_snapshot(character: Character, snapshot_json: dict[str, Any]) -> None:
    basic = snapshot_json.get("character_basic") or {}
    changed_fields = []
    field_map = {
        "character_name": basic.get("character_name"),
        "world_name": basic.get("world_name"),
        "character_class": basic.get("character_class"),
        "character_class_level": basic.get("character_class_level"),
        "character_level": basic.get("character_level"),
    }
    for field_name, value in field_map.items():
        if value not in (None, "") and getattr(character, field_name) != value:
            setattr(character, field_name, value)
            changed_fields.append(field_name)
    character.last_synced_at = timezone.now()
    changed_fields.append("last_synced_at")
    character.save(update_fields=changed_fields)


def extract_combat_power(stat: dict[str, Any]) -> Any:
    direct_value = stat.get("combat_power")
    if direct_value not in (None, ""):
        return direct_value

    final_stats = stat.get("final_stat")
    if not isinstance(final_stats, list):
        return ""
    for item in final_stats:
        if not isinstance(item, dict):
            continue
        if item.get("stat_name") in ("전투력", "combat_power"):
            return item.get("stat_value", "")
    return ""


def stringify_or_blank(value: Any) -> str:
    if value in (None, ""):
        return ""
    return str(value)


def end_play_session(
    *,
    session: PlaySession,
    ended_at: datetime | None = None,
    end_snapshot: CharacterSnapshot | None = None,
) -> PlaySession:
    ended_at = ended_at or timezone.now()
    session.ended_at = ended_at
    session.end_snapshot = end_snapshot or session.end_snapshot
    session.play_minutes = minutes_between(session.started_at, ended_at)
    session.status = PlaySession.Status.ENDED
    session.save(update_fields=["ended_at", "end_snapshot", "play_minutes", "status", "updated_at"])
    return session


def latest_snapshot_before(character: Character, before_date: date) -> CharacterSnapshot | None:
    return (
        CharacterSnapshot.objects.filter(character=character, play_date__lt=before_date)
        .order_by("-play_date", "-recorded_at")
        .first()
    )


def latest_snapshot_on_or_before(character: Character, target_date: date) -> CharacterSnapshot | None:
    return (
        CharacterSnapshot.objects.filter(character=character, play_date__lte=target_date)
        .order_by("-play_date", "-recorded_at")
        .first()
    )


def latest_snapshot_for_date(character: Character, target_date: date) -> CharacterSnapshot | None:
    return (
        CharacterSnapshot.objects.filter(character=character, play_date=target_date)
        .order_by("-recorded_at")
        .first()
    )


def numeric_delta(end_value: Any, start_value: Any) -> str:
    if end_value in (None, "") or start_value in (None, ""):
        return ""
    try:
        return str(int(str(end_value).replace(",", "")) - int(str(start_value).replace(",", "")))
    except ValueError:
        return ""


def build_change_summary(start_snapshot: CharacterSnapshot | None, end_snapshot: CharacterSnapshot | None) -> dict[str, Any]:
    if not end_snapshot:
        return {"status": "missing_end_snapshot", "changes": []}
    if not start_snapshot:
        return {"status": "baseline", "changes": [], "message": "비교할 이전 스냅샷이 없어 기준 리포트로 저장한다."}

    changes = []
    watched_fields = [
        ("character_level", "레벨"),
        ("character_exp", "경험치"),
        ("exp_rate", "경험치 퍼센트"),
        ("combat_power", "전투력"),
    ]
    for field_name, label in watched_fields:
        before = getattr(start_snapshot, field_name)
        after = getattr(end_snapshot, field_name)
        if before != after:
            changes.append({"field": field_name, "label": label, "before": before, "after": after})

    start_json = start_snapshot.snapshot_json or {}
    end_json = end_snapshot.snapshot_json or {}
    for key in sorted(set(start_json.keys()) | set(end_json.keys())):
        if start_json.get(key) != end_json.get(key):
            changes.append({"field": f"snapshot_json.{key}", "label": key, "changed": True})

    return {"status": "compared", "changes": changes}


def report_period(report_type: str, report_date: date) -> tuple[date, date, date]:
    if report_type == Report.ReportType.DAILY:
        period_start = report_date
        period_end = report_date
        compare_start = report_date - timedelta(days=1)
    elif report_type == Report.ReportType.WEEKLY:
        period_end = report_date
        period_start = report_date - timedelta(days=6)
        compare_start = report_date - timedelta(days=7)
    elif report_type == Report.ReportType.MONTHLY:
        period_end = report_date
        period_start = report_date.replace(day=1)
        compare_start = period_start - timedelta(days=1)
    else:
        raise ValueError(f"Unsupported report type: {report_type}")
    return period_start, period_end, compare_start


def create_report(*, character: Character, report_type: str, report_date: date) -> Report:
    period_start, period_end, compare_start = report_period(report_type, report_date)
    start_snapshot = latest_snapshot_on_or_before(character, compare_start)
    end_snapshot = latest_snapshot_on_or_before(character, period_end)
    sessions = PlaySession.objects.filter(
        character=character,
        status=PlaySession.Status.ENDED,
        play_date__gte=period_start,
        play_date__lte=period_end,
    )
    play_minutes = sessions.aggregate(total=Sum("play_minutes"))["total"] or 0
    first_started_at = sessions.order_by("started_at").values_list("started_at", flat=True).first()
    summary = build_change_summary(start_snapshot, end_snapshot)
    summary["play_time"] = {
        "first_started_at": first_started_at.isoformat() if first_started_at else None,
        "total_minutes": play_minutes,
    }

    report, _created = Report.objects.update_or_create(
        character=character,
        report_type=report_type,
        report_date=report_date,
        defaults={
            "period_start": period_start,
            "period_end": period_end,
            "start_snapshot": start_snapshot,
            "end_snapshot": end_snapshot,
            "first_started_at": first_started_at,
            "play_minutes": play_minutes,
            "level_delta": (end_snapshot.character_level - start_snapshot.character_level)
            if start_snapshot and end_snapshot and start_snapshot.character_level and end_snapshot.character_level
            else None,
            "exp_delta": numeric_delta(
                end_snapshot.character_exp if end_snapshot else None,
                start_snapshot.character_exp if start_snapshot else None,
            ),
            "combat_power_delta": numeric_delta(
                end_snapshot.combat_power if end_snapshot else None,
                start_snapshot.combat_power if start_snapshot else None,
            ),
            "summary_json": summary,
        },
    )
    return report


def scheduler_state(snapshot: CharacterSnapshot | None) -> dict[str, Any]:
    if not snapshot:
        return {}
    data = snapshot.snapshot_json or {}
    return data.get("scheduler_character_state") or data.get("scheduler") or data


def find_missing_scheduler_tasks(snapshot: CharacterSnapshot | None) -> dict[str, list[dict[str, Any]]]:
    state = scheduler_state(snapshot)
    result = {"daily": [], "weekly": [], "boss": []}
    if not isinstance(state, dict):
        return result

    candidates = {
        "daily": ["daily", "daily_quest", "daily_quests", "daily_contents"],
        "weekly": ["weekly", "weekly_quest", "weekly_quests", "weekly_contents"],
        "boss": ["boss", "bosses"],
    }
    for target, keys in candidates.items():
        for key in keys:
            value = state.get(key)
            if isinstance(value, list):
                result[target].extend([item for item in value if is_incomplete_task(item)])
    return result


def is_incomplete_task(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    if item.get("is_clear") is False or item.get("complete") is False or item.get("completed") is False:
        return True
    current = first_present(item, ["current_count", "current_score"])
    maximum = first_present(item, ["max_count", "max_score"])
    if current is not None and maximum is not None:
        try:
            return int(current) < int(maximum)
        except (TypeError, ValueError):
            return False
    return False


def first_present(item: dict[str, Any], keys: list[str]) -> Any:
    for key in keys:
        if key in item:
            return item[key]
    return None

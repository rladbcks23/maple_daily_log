import re

from django.utils import timezone

from .models import NoticeSnapshot, SelectedCharacter
from .nexon import NexonClient


THUMBNAIL_KEYS = [
    "thumbnail",
    "thumbnail_url",
    "thumbnailUrl",
    "thumbnail_image",
    "thumbnailImage",
    "image",
    "image_url",
    "imageUrl",
    "banner_image",
    "bannerImage",
    "event_image",
    "eventImage",
    "event_thumbnail",
    "eventThumbnail",
    "event_thumbnail_url",
    "eventThumbnailUrl",
    "cashshop_thumbnail",
    "cashshopThumbnail",
    "cashshop_thumbnail_url",
    "cashshopThumbnailUrl",
]


def first_value(data, keys, default=None):
    for key in keys:
        if isinstance(data, dict) and key in data:
            return data[key]
    return default


def normalize_notice_items(notice_type, payload):
    raw_items = first_value(
        payload,
        ["notice", "notice_list", "event_notice", "cashshop_notice", "update_notice"],
        [],
    )
    if isinstance(payload, list):
        raw_items = payload
    if not isinstance(raw_items, list):
        raw_items = []

    items = []
    for item in raw_items:
        notice_id = str(
            first_value(
                item,
                ["notice_id", "event_notice_id", "cashshop_notice_id", "update_notice_id", "id"],
                "",
            )
        )
        title = first_value(item, ["title", "notice_title"], "")
        link = first_value(item, ["url", "link", "notice_url"], "")
        registered_at = first_value(item, ["date", "notice_date", "registered_at"], "")
        thumbnail = first_value(item, THUMBNAIL_KEYS, "")
        event_start_at = first_value(item, ["date_event_start", "event_start_at", "eventStartAt"], "")
        event_end_at = first_value(item, ["date_event_end", "event_end_at", "eventEndAt"], "")
        sale_start_at = first_value(item, ["date_sale_start", "sale_start_at", "saleStartAt"], "")
        sale_end_at = first_value(item, ["date_sale_end", "sale_end_at", "saleEndAt"], "")
        sale_ongoing = first_value(
            item,
            ["ongoing_flag", "ongoingFlag", "is_ongoing", "isOngoing", "always_sale", "alwaysSale"],
            "",
        )
        if not notice_id and title:
            notice_id = f"{notice_type}:{title}:{registered_at}"
        if notice_id:
            normalized = {
                "noticeType": notice_type,
                "noticeId": notice_id,
                "title": title,
                "link": link,
                "registeredAt": registered_at,
                "thumbnail": thumbnail,
                "thumbnailUrl": thumbnail,
            }
            if event_start_at:
                normalized["eventStartAt"] = event_start_at
            if event_end_at:
                normalized["eventEndAt"] = event_end_at
            if sale_start_at:
                normalized["saleStartAt"] = sale_start_at
            if sale_end_at:
                normalized["saleEndAt"] = sale_end_at
            if sale_ongoing != "":
                normalized["saleOngoing"] = sale_ongoing
            items.append(normalized)
    return items


def first_image_url(payload):
    if not isinstance(payload, dict):
        return ""

    direct = first_value(payload, THUMBNAIL_KEYS, "")
    if direct:
        return direct

    body = first_value(payload, ["contents", "content", "body", "notice_contents"], "")
    if not isinstance(body, str):
        return ""

    match = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', body, re.IGNORECASE)
    return match.group(1) if match else ""


def image_urls_from_content(content):
    if not isinstance(content, str):
        return []

    return re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', content, re.IGNORECASE)


def fill_event_details(items, client):
    for item in items:
        if item.get("noticeType") != "event":
            continue

        needs_thumbnail = not item.get("thumbnail")
        needs_sunday_content = item.get("title") == "스페셜 썬데이 메이플"
        if not needs_thumbnail and not needs_sunday_content:
            continue

        try:
            detail = client.event_detail(item["noticeId"])
        except Exception:
            continue

        if needs_thumbnail:
            thumbnail = first_image_url(detail)
            item["thumbnail"] = thumbnail
            item["thumbnailUrl"] = thumbnail

        if needs_sunday_content:
            content = first_value(detail, ["contents", "content", "body", "notice_contents"], "")
            item["content"] = content
            item["contentImageUrls"] = image_urls_from_content(content)


def collect_current_notice_items(client=None):
    client = client or NexonClient()
    items = []
    for notice_type, payload in client.current_notices().items():
        normalized = normalize_notice_items(notice_type, payload)
        if notice_type == "event":
            fill_event_details(normalized, client)
        items.extend(normalized)
    return items


def check_new_notices(client=None):
    current_items = collect_current_notice_items(client)
    existing_ids = set(NoticeSnapshot.objects.values_list("notice_type", "notice_id"))
    new_items = [
        item for item in current_items
        if (item["noticeType"], item["noticeId"]) not in existing_ids
    ]

    NoticeSnapshot.objects.all().delete()
    NoticeSnapshot.objects.bulk_create(
        [
            NoticeSnapshot(
                notice_type=item["noticeType"],
                notice_id=item["noticeId"],
                title=item["title"],
                link=item["link"],
                registered_at=item["registeredAt"],
            )
            for item in current_items
        ],
        ignore_conflicts=True,
    )
    return {
        "shouldNotify": bool(new_items),
        "newItems": new_items,
        "snapshotCount": len(current_items),
    }


def is_done_item(item):
    if not isinstance(item, dict):
        return False

    done = first_value(item, ["is_completed", "completed", "clear_status", "is_clear"])
    if isinstance(done, bool):
        return done
    if isinstance(done, str) and done.lower() in ["true", "complete", "completed", "done", "2"]:
        return True

    progress_state = first_value(item, ["quest_state", "state", "progress_state"])
    if str(progress_state) == "2":
        return True

    current = first_value(item, ["current_count", "current_score", "current_complete_count", "done_count"])
    maximum = first_value(item, ["max_count", "max_score", "maximum_count", "limit_count"])
    try:
        if current is not None and maximum is not None:
            return float(current) >= float(maximum)
    except (TypeError, ValueError):
        pass

    return False


def item_name(item, fallback):
    return first_value(item, ["contents_name", "content_name", "quest_name", "boss_name", "name", "title"], fallback)


def build_missing_items(items, category):
    missing = []
    for index, item in enumerate(items or []):
        if not is_done_item(item):
            missing.append(
                {
                    "category": category,
                    "name": item_name(item, f"{category}-{index + 1}"),
                    "raw": item,
                }
            )
    return missing


def scheduler_daily_result(scheduler_payload):
    daily_contents = first_value(scheduler_payload, ["daily_contents"], [])
    boss_contents = first_value(scheduler_payload, ["boss_contents", "bosses"], [])

    unknown_items = []
    if not daily_contents:
        unknown_items.append(
            {
                "category": "daily",
                "name": "일간 콘텐츠 정보",
                "reason": "daily_contents is empty",
            }
        )

    missing_items = build_missing_items(daily_contents, "daily")
    daily_bosses = [
        boss for boss in boss_contents or []
        if str(first_value(boss, ["reset_cycle", "boss_reset_cycle", "cycle"], "")).lower() in ["daily", "day", "일간", "일일"]
    ]
    missing_items.extend(build_missing_items(daily_bosses, "daily_boss"))
    return {"unknownItems": unknown_items, "missingItems": missing_items}


def scheduler_weekly_result(scheduler_payload):
    weekly_contents = first_value(scheduler_payload, ["weekly_contents"], [])
    boss_contents = first_value(scheduler_payload, ["boss_contents", "bosses"], [])

    weekly_unknown_items = []
    if not weekly_contents:
        weekly_unknown_items.append(
            {
                "category": "weekly",
                "name": "주간 콘텐츠 정보",
                "reason": "weekly_contents is empty",
            }
        )

    weekly_missing_items = build_missing_items(weekly_contents, "weekly")
    weekly_bosses = [
        boss for boss in boss_contents or []
        if str(first_value(boss, ["reset_cycle", "boss_reset_cycle", "cycle"], "")).lower() in ["weekly", "week", "주간"]
    ]
    weekly_missing_items.extend(build_missing_items(weekly_bosses, "weekly_boss"))
    return {"weeklyUnknownItems": weekly_unknown_items, "weeklyMissingItems": weekly_missing_items}


def selected_characters_for_request(ocid=None):
    queryset = SelectedCharacter.objects.all()
    if ocid:
        queryset = queryset.filter(ocid=ocid)
    return list(queryset)


def build_reminder_result(character, scheduler_payload, mode):
    daily = scheduler_daily_result(scheduler_payload)
    weekly = scheduler_weekly_result(scheduler_payload)
    result = {
        "character": {
            "id": character.id,
            "characterName": character.character_name,
            "worldName": character.world_name,
            "ocid": character.ocid,
        },
        "mode": mode,
        "shouldNotify": False,
        "unknownItems": [],
        "missingItems": [],
        "weeklyUnknownItems": [],
        "weeklyMissingItems": [],
        "message": "",
    }

    if mode == "daily":
        result["unknownItems"] = daily["unknownItems"]
        result["shouldNotify"] = bool(result["unknownItems"])
        result["message"] = "접속해서 오늘 숙제를 확인해 주세요." if result["shouldNotify"] else ""
    elif mode == "launcher_exit":
        result["missingItems"] = daily["missingItems"]
        result["unknownItems"] = daily["unknownItems"]
        result["shouldNotify"] = bool(result["missingItems"])
        result["message"] = "아직 완료하지 않은 일일 숙제가 있어요." if result["shouldNotify"] else ""
    elif mode == "weekly":
        result["weeklyUnknownItems"] = weekly["weeklyUnknownItems"]
        result["weeklyMissingItems"] = weekly["weeklyMissingItems"]
        result["shouldNotify"] = bool(result["weeklyMissingItems"] or result["weeklyUnknownItems"])
        if result["weeklyMissingItems"]:
            result["message"] = "목요일 전에 주간 숙제를 완료해 주세요."
        elif result["weeklyUnknownItems"]:
            result["message"] = "이번 주 숙제를 확인해 주세요."

    return result


def run_reminder_check(mode, ocid=None, date=None, client=None, force=False):
    client = client or NexonClient()
    if mode == "weekly" and not force:
        weekday = timezone.localdate().weekday()
        if weekday not in [1, 2]:
            return {
                "mode": mode,
                "shouldCheck": False,
                "reason": "weekly checks only run on Tuesday or Wednesday",
                "results": [],
            }

    results = []
    for character in selected_characters_for_request(ocid):
        scheduler_payload = client.scheduler(character.ocid, date=date)
        results.append(build_reminder_result(character, scheduler_payload, mode))

    return {
        "mode": mode,
        "shouldCheck": True,
        "shouldNotify": any(result["shouldNotify"] for result in results),
        "results": results,
    }


def update_character_from_basic(character, basic):
    character.character_name = first_value(basic, ["character_name"], character.character_name)
    character.world_name = first_value(basic, ["world_name"], character.world_name)
    character.character_class = first_value(basic, ["character_class"], character.character_class)
    character.character_level = first_value(basic, ["character_level"], character.character_level)
    character.character_image = first_value(basic, ["character_image"], character.character_image)
    character.save()
    return character

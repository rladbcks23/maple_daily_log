import re
from concurrent.futures import ThreadPoolExecutor
from html import unescape
from types import SimpleNamespace

import requests
from django.utils import timezone

from .models import NoticeSnapshot, SundayEventSnapshot
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

CLOSED_EVENT_LIST_URL = "https://maplestory.nexon.com/News/Event/Closed"
_CLOSED_EVENT_ITEM_PATTERN = re.compile(
    r'<li>\s*<div class="event_list_wrap">(?P<item>.*?)</div>\s*</li>',
    re.IGNORECASE | re.DOTALL,
)
_CLOSED_EVENT_LINK_PATTERN = re.compile(
    r'href="(?P<link>/News/Event/Closed/(?P<notice_id>\d+))"',
    re.IGNORECASE,
)
_CLOSED_EVENT_TITLE_PATTERN = re.compile(
    r'class="event_listMt"[^>]*>(?P<title>.*?)</em>',
    re.IGNORECASE | re.DOTALL,
)
_CLOSED_EVENT_THUMBNAIL_PATTERN = re.compile(
    r'<img\s+src="(?P<thumbnail>[^"]+)"',
    re.IGNORECASE,
)
_CLOSED_EVENT_DATE_PATTERN = re.compile(r"\d{4}\.\d{2}\.\d{2}")
_CLOSED_EVENT_CONTENT_PATTERN = re.compile(
    r'<div class="qs_text">\s*<div class="new_board_con">(?P<content>.*?)</div>\s*</div>',
    re.IGNORECASE | re.DOTALL,
)


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


def _html_text(value):
    return re.sub(r"<[^>]+>", "", unescape(value or "")).strip()


def is_sunday_maple_title(title):
    return title in {"스페셜 썬데이 메이플", "썬데이 메이플"}


def _closed_event_content(link, timeout):
    try:
        response = requests.get(link, timeout=timeout)
        response.raise_for_status()
    except requests.RequestException:
        return ""

    match = _CLOSED_EVENT_CONTENT_PATTERN.search(response.text)
    return match.group("content") if match is not None else ""


def collect_latest_closed_sunday_event(client=None):
    client = client or NexonClient()
    try:
        response = requests.get(CLOSED_EVENT_LIST_URL, timeout=client.timeout)
        response.raise_for_status()
    except requests.RequestException:
        return None

    for match in _CLOSED_EVENT_ITEM_PATTERN.finditer(response.text):
        item_html = match.group("item")
        link_match = _CLOSED_EVENT_LINK_PATTERN.search(item_html)
        title_match = _CLOSED_EVENT_TITLE_PATTERN.search(item_html)
        if link_match is None or title_match is None:
            continue

        title = _html_text(title_match.group("title"))
        if not is_sunday_maple_title(title):
            continue

        thumbnail_match = _CLOSED_EVENT_THUMBNAIL_PATTERN.search(item_html)
        dates = _CLOSED_EVENT_DATE_PATTERN.findall(item_html)
        event_start_at = dates[0].replace(".", "-") if dates else ""
        event_end_at = dates[1].replace(".", "-") if len(dates) > 1 else event_start_at
        link = f"https://maplestory.nexon.com{link_match.group('link')}"
        content = _closed_event_content(link, client.timeout)
        thumbnail = (
            thumbnail_match.group("thumbnail")
            if thumbnail_match is not None
            else ""
        )

        return {
            "noticeType": "event",
            "noticeId": link_match.group("notice_id"),
            "title": title,
            "link": link,
            "registeredAt": event_start_at,
            "thumbnail": thumbnail,
            "thumbnailUrl": thumbnail,
            "eventStartAt": event_start_at,
            "eventEndAt": event_end_at,
            "content": content,
            "contentImageUrls": image_urls_from_content(content),
        }

    return None


def sunday_event_to_payload(snapshot):
    if snapshot is None:
        return None
    return {
        "noticeType": "event",
        "noticeId": snapshot.notice_id,
        "title": snapshot.title,
        "link": snapshot.link,
        "registeredAt": snapshot.registered_at,
        "thumbnail": snapshot.thumbnail,
        "thumbnailUrl": snapshot.thumbnail,
        "eventStartAt": snapshot.event_start_at,
        "eventEndAt": snapshot.event_end_at,
        "content": snapshot.content,
        "contentImageUrls": snapshot.content_image_urls,
    }


def latest_sunday_event_snapshot():
    return SundayEventSnapshot.objects.order_by("-event_start_at", "-registered_at").first()


def save_sunday_event_snapshot(event):
    if not event:
        return None
    snapshot, _ = SundayEventSnapshot.objects.update_or_create(
        notice_id=event["noticeId"],
        defaults={
            "title": event.get("title", ""),
            "link": event.get("link", ""),
            "registered_at": event.get("registeredAt", ""),
            "thumbnail": event.get("thumbnail", "") or event.get("thumbnailUrl", ""),
            "event_start_at": event.get("eventStartAt", ""),
            "event_end_at": event.get("eventEndAt", ""),
            "content": event.get("content", ""),
            "content_image_urls": event.get("contentImageUrls", []),
        },
    )
    return snapshot


def collect_or_load_latest_sunday_event(client=None, force_refresh=False):
    if not force_refresh:
        cached_snapshot = latest_sunday_event_snapshot()
        if cached_snapshot is not None:
            return sunday_event_to_payload(cached_snapshot)

    event = collect_latest_closed_sunday_event(client)
    snapshot = save_sunday_event_snapshot(event)
    return sunday_event_to_payload(snapshot)


def fill_event_details(items, client):
    targets = []
    for item in items:
        needs_thumbnail = not item.get("thumbnail")
        needs_sunday_content = is_sunday_maple_title(item.get("title"))
        if item.get("noticeType") == "event" and (
            needs_thumbnail or needs_sunday_content
        ):
            targets.append(item)

    def fetch_detail(item):
        try:
            return item, client.event_detail(item["noticeId"])
        except Exception:
            return item, None

    if not targets:
        return

    with ThreadPoolExecutor(max_workers=min(4, len(targets))) as executor:
        details = executor.map(fetch_detail, targets)

    for item, detail in details:
        if detail is None:
            continue
        needs_thumbnail = not item.get("thumbnail")
        needs_sunday_content = is_sunday_maple_title(item.get("title"))
        if needs_thumbnail:
            thumbnail = first_image_url(detail)
            item["thumbnail"] = thumbnail
            item["thumbnailUrl"] = thumbnail

        if needs_sunday_content:
            content = first_value(detail, ["contents", "content", "body", "notice_contents"], "")
            item["content"] = content
            item["contentImageUrls"] = image_urls_from_content(content)
            save_sunday_event_snapshot(item)


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
    if not ocid:
        return []
    return [
        SimpleNamespace(
            id=None,
            character_name="",
            world_name="",
            ocid=ocid,
        )
    ]


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

import tempfile
from unittest.mock import patch

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from .models import Feedback, NoticeSnapshot, SundayEventSnapshot
from .services import (
    check_new_notices,
    collect_and_store_notice_items,
)


class NoticeSnapshotTests(TestCase):
    def test_check_new_notices_returns_only_new_items_and_updates_snapshot(self):
        NoticeSnapshot.objects.create(
            notice_type="notice",
            notice_id="old",
            title="기존 공지",
            link="https://example.com/old",
            registered_at="2026-07-13",
        )

        class FakeClient:
            def current_notices(self):
                return {
                    "notice": {
                        "notice": [
                            {
                                "notice_id": "old",
                                "title": "기존 공지",
                                "url": "https://example.com/old",
                                "date": "2026-07-13",
                            },
                            {
                                "notice_id": "new",
                                "title": "새 공지",
                                "url": "https://example.com/new",
                                "date": "2026-07-14",
                            },
                        ]
                    },
                    "event": [],
                    "cashshop": [],
                    "update": [],
                }

        result = check_new_notices(FakeClient())

        self.assertTrue(result["shouldNotify"])
        self.assertEqual([item["noticeId"] for item in result["newItems"]], ["new"])
        self.assertEqual(NoticeSnapshot.objects.count(), 2)

    def test_missing_active_event_stays_until_end_date(self):
        NoticeSnapshot.objects.create(
            notice_type="event",
            notice_id="event-1",
            title="active event",
            link="https://example.com/event-1",
            registered_at="2026-08-01",
            event_end_at="2099-12-31",
            is_active=True,
        )

        class FakeClient:
            def current_notices(self):
                return {
                    "notice": [],
                    "event": [],
                    "cashshop": [],
                    "update": [],
                }

        result = collect_and_store_notice_items(FakeClient())

        self.assertEqual(
            [item["noticeId"] for item in result["items"]],
            ["event-1"],
        )
        self.assertTrue(NoticeSnapshot.objects.get(notice_id="event-1").is_active)

    def test_ended_event_is_marked_inactive_and_reported_once(self):
        NoticeSnapshot.objects.create(
            notice_type="event",
            notice_id="event-1",
            title="ended event",
            link="https://example.com/event-1",
            registered_at="2026-07-01",
            event_end_at="2000-01-01",
            is_active=True,
            ended_notified=False,
        )

        class FakeClient:
            def current_notices(self):
                return {
                    "notice": [],
                    "event": [],
                    "cashshop": [],
                    "update": [],
                }

        result = collect_and_store_notice_items(FakeClient())
        second_result = collect_and_store_notice_items(FakeClient())

        snapshot = NoticeSnapshot.objects.get(notice_id="event-1")
        self.assertFalse(snapshot.is_active)
        self.assertTrue(snapshot.ended_notified)
        self.assertEqual(
            [item["noticeId"] for item in result["endedEvents"]],
            ["event-1"],
        )
        self.assertEqual(second_result["endedEvents"], [])


class ApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def test_health(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_latest_sunday_uses_database_snapshot(self):
        SundayEventSnapshot.objects.create(
            notice_id="sunday-1",
            title="썬데이 메이플",
            link="https://example.com/sunday",
            registered_at="2026-07-19",
            thumbnail="https://example.com/sunday.png",
            event_start_at="2026-07-19",
            event_end_at="2026-07-19",
            content="<img src='https://example.com/content.png'>",
            content_image_urls=["https://example.com/content.png"],
        )

        response = self.client.get("/api/notices/latest-sunday")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["noticeId"], "sunday-1")

    @patch("api.views.NexonClient.character_basic")
    def test_character_basic_uses_server_cache(self, character_basic):
        character_basic.return_value = {
            "character_name": "테스트캐릭",
            "world_name": "스카니아",
        }

        first = self.client.get(
            "/api/nexon/characters/ocid-1/basic",
            HTTP_X_NEXON_API_KEY="test-key",
        )
        second = self.client.get(
            "/api/nexon/characters/ocid-1/basic",
            HTTP_X_NEXON_API_KEY="test-key",
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(character_basic.call_count, 1)

    @patch("api.views.NexonClient.character_basic")
    def test_character_basic_refresh_bypasses_server_cache(
        self,
        character_basic,
    ):
        character_basic.return_value = {
            "character_name": "테스트캐릭",
            "world_name": "스카니아",
        }

        self.client.get(
            "/api/nexon/characters/ocid-1/basic",
            HTTP_X_NEXON_API_KEY="test-key",
        )
        refreshed = self.client.get(
            "/api/nexon/characters/ocid-1/basic",
            {"refresh": "1"},
            HTTP_X_NEXON_API_KEY="test-key",
        )

        self.assertEqual(refreshed.status_code, 200)
        self.assertEqual(character_basic.call_count, 2)

    def test_feedback_create_saves_content(self):
        response = self.client.post(
            "/api/feedback",
            {"content": "  버튼이 잘 안 눌려요  ", "appVersion": "0.2.0"},
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(Feedback.objects.count(), 1)
        feedback = Feedback.objects.get()
        self.assertEqual(feedback.content, "버튼이 잘 안 눌려요")

    def test_feedback_create_rejects_blank_content(self):
        response = self.client.post(
            "/api/feedback", {"content": "   "}, format="json"
        )

        self.assertEqual(response.status_code, 400)

    @override_settings(MEDIA_ROOT=tempfile.mkdtemp())
    def test_feedback_create_accepts_image_attachment(self):
        image = SimpleUploadedFile(
            "screenshot.png", b"fake-image-bytes", content_type="image/png"
        )

        response = self.client.post(
            "/api/feedback",
            {"content": "스크린샷 첨부", "attachment": image},
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        feedback = Feedback.objects.get()
        self.assertTrue(feedback.attachment.name.startswith("feedback_attachments/"))

    def test_feedback_create_rejects_non_media_attachment(self):
        text_file = SimpleUploadedFile(
            "notes.txt", b"not media", content_type="text/plain"
        )

        response = self.client.post(
            "/api/feedback",
            {"content": "잘못된 첨부", "attachment": text_file},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(Feedback.objects.count(), 0)
        self.assertEqual(Feedback.objects.count(), 0)

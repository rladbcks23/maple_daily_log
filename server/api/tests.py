from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from .models import NoticeSnapshot, SelectedCharacter
from .services import check_new_notices, scheduler_daily_result, scheduler_weekly_result


class SchedulerResultTests(TestCase):
    def test_empty_daily_contents_becomes_unknown(self):
        result = scheduler_daily_result({"daily_contents": []})

        self.assertEqual(result["unknownItems"][0]["name"], "일간 콘텐츠 정보")
        self.assertEqual(result["missingItems"], [])

    def test_incomplete_daily_content_becomes_missing(self):
        result = scheduler_daily_result(
            {
                "daily_contents": [
                    {
                        "contents_name": "몬스터 파크",
                        "current_count": 0,
                        "max_count": 2,
                    }
                ]
            }
        )

        self.assertEqual(result["unknownItems"], [])
        self.assertEqual(result["missingItems"][0]["name"], "몬스터 파크")

    def test_empty_weekly_contents_becomes_weekly_unknown(self):
        result = scheduler_weekly_result({"weekly_contents": []})

        self.assertEqual(result["weeklyUnknownItems"][0]["name"], "주간 콘텐츠 정보")
        self.assertEqual(result["weeklyMissingItems"], [])


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


class ApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_health(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_selected_characters_list(self):
        SelectedCharacter.objects.create(
            character_name="테스트캐릭",
            world_name="스카니아",
            ocid="ocid-1",
            character_class="비숍",
            character_level=260,
        )

        response = self.client.get("/api/selected-characters/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["character_name"], "테스트캐릭")

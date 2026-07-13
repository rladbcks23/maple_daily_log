from django.test import TestCase
from rest_framework.test import APIClient

from .models import CHARACTER_TAG_IGNORE, CHARACTER_TAG_MAIN, CHARACTER_TAG_SUB, CHARACTER_TAG_WEEKLY_BOSS, Character
from .services import collection_candidates, sync_character_snapshot_from_nexon, sync_character_snapshots_from_nexon, sync_characters_from_nexon
from .nexon import extract_character_list


class PlanningFlowTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_play_session_and_daily_report_flow(self):
        character_response = self.client.post(
            "/api/characters",
            {
                "ocid": "test-ocid",
                "character_name": "테스트",
                "world_name": "스카니아",
                "character_class": "아델",
                "character_level": 260,
            },
            format="json",
        )
        self.assertEqual(character_response.status_code, 201)
        character_id = character_response.data["id"]
        self.assertEqual(character_response.data["tags"], [CHARACTER_TAG_IGNORE])

        snapshot_response = self.client.post(
            "/api/snapshots",
            {
                "character": character_id,
                "snapshot_type": "game_end",
                "bundle_name": "daily",
                "play_date": "2026-07-10",
                "character_level": 260,
                "character_exp": "1000",
                "exp_rate": "10.5",
                "combat_power": "123456",
                "snapshot_json": {
                    "scheduler_character_state": {
                        "daily": [
                            {
                                "name": "일일 퀘스트",
                                "current_count": 0,
                                "max_count": 1,
                            }
                        ]
                    }
                },
            },
            format="json",
        )
        self.assertEqual(snapshot_response.status_code, 201)
        snapshot_id = snapshot_response.data["id"]

        session_response = self.client.post(
            "/api/play-sessions/start",
            {
                "character": character_id,
                "play_date": "2026-07-10",
                "started_at": "2026-07-10T10:00:00+09:00",
            },
            format="json",
        )
        self.assertEqual(session_response.status_code, 201)
        session_id = session_response.data["id"]

        end_response = self.client.post(
            f"/api/play-sessions/{session_id}/end",
            {
                "ended_at": "2026-07-10T11:30:00+09:00",
                "end_snapshot": snapshot_id,
            },
            format="json",
        )
        self.assertEqual(end_response.status_code, 200)
        self.assertEqual(end_response.data["play_minutes"], 90)
        self.assertEqual(len(end_response.data["missing_tasks"]["daily"]), 1)

        report_response = self.client.post(
            "/api/reports/daily",
            {
                "report_date": "2026-07-10",
                "character_ids": [character_id],
            },
            format="json",
        )
        self.assertEqual(report_response.status_code, 201)
        self.assertEqual(report_response.data[0]["play_minutes"], 90)
        self.assertEqual(report_response.data[0]["summary_json"]["play_time"]["total_minutes"], 90)

    def test_browser_requests_return_json_without_template_renderer(self):
        response = self.client.get("/api/characters", HTTP_ACCEPT="text/html")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/json")
        self.assertEqual(response.json(), [])

    def test_sync_characters_get_describes_post_usage(self):
        response = self.client.get("/api/sync/characters")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["method"], "POST")

    def test_sync_characters_from_nexon_upserts_character_list(self):
        class FakeNexonClient:
            def character_list(self):
                return [
                    {
                        "ocid": "ocid-1",
                        "character_name": "본캐",
                        "world_name": "스카니아",
                        "character_class": "아델",
                        "character_class_level": "6",
                        "character_level": 280,
                    }
                ]

        result = sync_characters_from_nexon(client=FakeNexonClient())

        self.assertEqual(result["created"], 1)
        self.assertEqual(result["updated"], 0)
        self.assertEqual(result["total"], 1)
        character = Character.objects.get(ocid="ocid-1")
        self.assertEqual(character.character_name, "본캐")
        self.assertEqual(character.character_level, 280)
        self.assertEqual(character.tags, [CHARACTER_TAG_IGNORE])

    def test_extract_character_list_supports_account_list_response(self):
        data = {
            "account_list": [
                {
                    "account_id": "hidden",
                    "character_list": [
                        {
                            "ocid": "ocid-1",
                            "character_name": "본캐",
                            "world_name": "스카니아",
                            "character_class": "아델",
                            "character_level": 280,
                        }
                    ],
                }
            ]
        }

        characters = extract_character_list(data)

        self.assertEqual(len(characters), 1)
        self.assertEqual(characters[0]["character_name"], "본캐")

    def test_sync_snapshot_get_describes_post_usage(self):
        response = self.client.get("/api/sync/snapshot")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["method"], "POST")

    def test_sync_character_snapshot_from_nexon_saves_bundle_result(self):
        character = Character.objects.create(
            ocid="ocid-snapshot",
            character_name="스냅샷캐릭",
            world_name="스카니아",
        )

        class FakeNexonClient:
            def collect_bundle_with_count(self, bundle_name, params):
                self.bundle_name = bundle_name
                self.params = params
                return (
                    {
                        "character_basic": {
                            "character_name": "스냅샷캐릭",
                            "world_name": "스카니아",
                            "character_class": "아델",
                            "character_class_level": "6",
                            "character_level": 280,
                            "character_exp": "123456",
                            "character_exp_rate": "12.34",
                        },
                        "character_stat": {
                            "final_stat": [
                                {
                                    "stat_name": "전투력",
                                    "stat_value": "987654321",
                                }
                            ]
                        },
                    },
                    2,
                )

        client = FakeNexonClient()
        result = sync_character_snapshot_from_nexon(
            character=character,
            bundle_name="light",
            snapshot_type="app_start",
            play_date="2026-07-10",
            client=client,
        )

        snapshot = result["snapshot"]
        character.refresh_from_db()
        self.assertEqual(result["api_calls_used"], 2)
        self.assertEqual(client.params["ocid"], "ocid-snapshot")
        self.assertEqual(snapshot.bundle_name, "light")
        self.assertEqual(snapshot.snapshot_type, "app_start")
        self.assertEqual(snapshot.character_level, 280)
        self.assertEqual(snapshot.character_exp, "123456")
        self.assertEqual(snapshot.exp_rate, "12.34")
        self.assertEqual(snapshot.combat_power, "987654321")
        self.assertEqual(character.character_class, "아델")
        self.assertEqual(character.character_level, 280)

    def test_collection_candidates_uses_character_classification_scope(self):
        main = Character.objects.create(ocid="main", character_name="본캐", tags=[CHARACTER_TAG_MAIN])
        sub = Character.objects.create(ocid="sub", character_name="부캐", tags=[CHARACTER_TAG_SUB])
        weekly = Character.objects.create(ocid="weekly", character_name="주보", tags=[CHARACTER_TAG_WEEKLY_BOSS])
        Character.objects.create(ocid="ignore", character_name="제외", tags=[CHARACTER_TAG_IGNORE])
        Character.objects.create(ocid="flagged", character_name="플래그", tags=[CHARACTER_TAG_MAIN], is_ignored=True)

        self.assertEqual(collection_candidates(collection_scope="main"), [main])
        self.assertEqual(collection_candidates(collection_scope="daily_report"), [main, sub])
        self.assertEqual(collection_candidates(collection_scope="weekly_report"), [main, weekly])
        self.assertEqual(collection_candidates(collection_scope="all_classified"), [main, sub, weekly])

    def test_sync_character_snapshots_from_nexon_collects_matching_scope_only(self):
        Character.objects.create(ocid="ignore", character_name="제외", tags=[CHARACTER_TAG_IGNORE])
        Character.objects.create(ocid="sub", character_name="부캐", tags=[CHARACTER_TAG_SUB])
        main = Character.objects.create(ocid="main", character_name="본캐", tags=[CHARACTER_TAG_MAIN])

        class FakeNexonClient:
            def collect_bundle_with_count(self, bundle_name, params):
                return (
                    {
                        "character_basic": {
                            "character_name": "본캐",
                            "world_name": "스카니아",
                            "character_class": "아델",
                            "character_level": 280,
                        },
                        "character_stat": {},
                    },
                    2,
                )

        result = sync_character_snapshots_from_nexon(
            bundle_name="light",
            snapshot_type="scheduled",
            play_date="2026-07-10",
            collection_scope="main",
            client=FakeNexonClient(),
        )

        self.assertEqual(result["total"], 1)
        self.assertEqual(result["api_calls_used"], 2)
        self.assertEqual(result["synced"][0].character, main)

    def test_characters_can_filter_by_tag(self):
        Character.objects.create(ocid="main", character_name="본캐", tags=[CHARACTER_TAG_MAIN])
        Character.objects.create(ocid="ignore", character_name="제외", tags=[CHARACTER_TAG_IGNORE])

        response = self.client.get(f"/api/characters?tag={CHARACTER_TAG_MAIN}")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["character_name"], "본캐")

    def test_character_tags_can_be_updated_with_supported_tags(self):
        character = Character.objects.create(ocid="tag-edit", character_name="태그변경")

        response = self.client.patch(
            f"/api/characters/{character.id}/tags",
            {"tags": [CHARACTER_TAG_MAIN]},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["tags"], [CHARACTER_TAG_MAIN])

    def test_character_tags_reject_unsupported_tags(self):
        character = Character.objects.create(ocid="tag-invalid", character_name="태그오류")

        response = self.client.patch(
            f"/api/characters/{character.id}/tags",
            {"tags": ["main"]},
            format="json",
        )

        self.assertEqual(response.status_code, 400)

    def test_character_tags_reject_multiple_tags(self):
        character = Character.objects.create(ocid="tag-multiple", character_name="태그여러개")

        response = self.client.patch(
            f"/api/characters/{character.id}/tags",
            {"tags": [CHARACTER_TAG_MAIN, CHARACTER_TAG_SUB]},
            format="json",
        )

        self.assertEqual(response.status_code, 400)

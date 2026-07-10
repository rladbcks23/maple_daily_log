from django.test import TestCase
from rest_framework.test import APIClient


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

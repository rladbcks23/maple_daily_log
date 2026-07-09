from dataclasses import dataclass
from datetime import datetime, timezone

import requests
from django.conf import settings


class NexonApiError(Exception):
    pass


@dataclass(frozen=True)
class NexonSnapshotBundle:
    ocid: str
    collected_at: datetime
    api_calls_used: int
    sections: dict


class NexonApiClient:
    SNAPSHOT_ENDPOINTS = {
        "basic": "/maplestory/v1/character/basic",
        "stat": "/maplestory/v1/character/stat",
        "hyperStat": "/maplestory/v1/character/hyper-stat",
        "ability": "/maplestory/v1/character/ability",
        "itemEquipment": "/maplestory/v1/character/item-equipment",
        "symbolEquipment": "/maplestory/v1/character/symbol-equipment",
        "vmatrix": "/maplestory/v1/character/vmatrix",
        "hexamatrix": "/maplestory/v1/character/hexamatrix",
        "hexamatrixStat": "/maplestory/v1/character/hexamatrix-stat",
    }

    def __init__(self):
        self.base_url = settings.MAPLE["NEXON_API_BASE_URL"].rstrip("/")
        self.api_key = settings.MAPLE["NEXON_API_KEY"]

    def fetch_character_list(self):
        body = self._get("/maplestory/v1/character/list")
        characters = []
        self._collect_characters(body, characters)
        return characters

    def fetch_snapshot_bundle(self, ocid):
        sections = {}
        for section, path in self.SNAPSHOT_ENDPOINTS.items():
            sections[section] = self._get(path, {"ocid": ocid})

        return NexonSnapshotBundle(
            ocid=ocid,
            collected_at=datetime.now(timezone.utc),
            api_calls_used=len(sections),
            sections=sections,
        )

    def _get(self, path, params=None):
        if not self.api_key:
            raise NexonApiError("NEXON_API_KEY is not configured.")

        response = requests.get(
            f"{self.base_url}{path}",
            params=params,
            headers={"x-nxopen-api-key": self.api_key},
            timeout=20,
        )

        if response.status_code >= 400:
            raise NexonApiError(f"Nexon API request failed with status {response.status_code}: {response.text}")

        try:
            return response.json()
        except ValueError as exc:
            raise NexonApiError("Nexon API returned a non-JSON response.") from exc

    def _collect_characters(self, node, characters):
        if node is None:
            return

        if isinstance(node, dict) and node.get("ocid"):
            characters.append(
                {
                    "ocid": node.get("ocid"),
                    "character_name": node.get("character_name") or node.get("ocid"),
                    "world_name": node.get("world_name"),
                    "character_class": node.get("character_class"),
                    "character_level": node.get("character_level"),
                }
            )
            return

        if isinstance(node, list):
            for child in node:
                self._collect_characters(child, characters)
            return

        if isinstance(node, dict):
            self._collect_characters(node.get("character_list"), characters)
            self._collect_characters(node.get("account_list"), characters)

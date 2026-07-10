from dataclasses import dataclass
from typing import Any

import requests
from django.conf import settings


NEXON_ENDPOINTS = {
    "id": "/maplestory/v1/id",
    "character_list": "/maplestory/v1/character/list",
    "character_basic": "/maplestory/v1/character/basic",
    "character_stat": "/maplestory/v1/character/stat",
    "character_hyper_stat": "/maplestory/v1/character/hyper-stat",
    "character_ability": "/maplestory/v1/character/ability",
    "character_item_equipment": "/maplestory/v1/character/item-equipment",
    "character_cashitem_equipment": "/maplestory/v1/character/cashitem-equipment",
    "character_symbol_equipment": "/maplestory/v1/character/symbol-equipment",
    "character_set_effect": "/maplestory/v1/character/set-effect",
    "character_skill": "/maplestory/v1/character/skill",
    "character_vmatrix": "/maplestory/v1/character/vmatrix",
    "character_hexamatrix": "/maplestory/v1/character/hexamatrix",
    "character_hexamatrix_stat": "/maplestory/v1/character/hexamatrix-stat",
    "character_other_stat": "/maplestory/v1/character/other-stat",
    "character_ring_exchange": "/maplestory/v1/character/ring-exchange-skill-equipment",
    "character_ring_reserve": "/maplestory/v1/character/ring-reserve-skill-equipment",
    "user_union": "/maplestory/v1/user/union",
    "user_union_artifact": "/maplestory/v1/user/union-artifact",
    "user_union_champion": "/maplestory/v1/user/union-champion",
    "history_starforce": "/maplestory/v1/history/starforce",
    "history_potential": "/maplestory/v1/history/potential",
    "history_cube": "/maplestory/v1/history/cube",
    "scheduler_character_state": "/maplestory/v1/scheduler/character-state",
}

SNAPSHOT_BUNDLES = {
    "light": [
        "character_basic",
        "character_stat",
        "scheduler_character_state",
    ],
    "daily": [
        "character_basic",
        "character_stat",
        "character_item_equipment",
        "character_symbol_equipment",
        "character_hexamatrix",
        "scheduler_character_state",
    ],
    "full": [
        "character_basic",
        "character_stat",
        "character_hyper_stat",
        "character_ability",
        "character_item_equipment",
        "character_cashitem_equipment",
        "character_symbol_equipment",
        "character_set_effect",
        "character_skill",
        "character_vmatrix",
        "character_hexamatrix",
        "character_hexamatrix_stat",
        "character_other_stat",
        "character_ring_exchange",
        "character_ring_reserve",
        "scheduler_character_state",
    ],
    "history": [
        "history_starforce",
        "history_potential",
        "history_cube",
    ],
}


@dataclass
class NexonClient:
    api_key: str = settings.NEXON_API_KEY
    base_url: str = settings.NEXON_API_BASE_URL

    def request(self, endpoint_key: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if endpoint_key not in NEXON_ENDPOINTS:
            raise ValueError(f"Unknown Nexon endpoint: {endpoint_key}")
        if not self.api_key:
            raise RuntimeError("NEXON_API_KEY is not configured")

        response = requests.get(
            f"{self.base_url}{NEXON_ENDPOINTS[endpoint_key]}",
            headers={"x-nxopen-api-key": self.api_key},
            params=params or {},
            timeout=10,
        )
        response.raise_for_status()
        return response.json()

    def collect_bundle(self, bundle_name: str, params: dict[str, Any]) -> dict[str, Any]:
        if bundle_name not in SNAPSHOT_BUNDLES:
            raise ValueError(f"Unknown snapshot bundle: {bundle_name}")
        return {
            endpoint_key: self.request(endpoint_key, params=params)
            for endpoint_key in SNAPSHOT_BUNDLES[bundle_name]
        }

    def character_list(self) -> list[dict[str, Any]]:
        data = self.request("character_list")
        raw_characters = extract_character_list(data)

        characters = []
        for raw_character in raw_characters:
            if not isinstance(raw_character, dict):
                continue
            character = normalize_character(raw_character)
            if not character.get("ocid") and character.get("character_name"):
                character["ocid"] = self.ocid(character["character_name"])
            if character.get("ocid") and character.get("character_name"):
                characters.append(character)
        return characters

    def ocid(self, character_name: str) -> str:
        data = self.request("id", params={"character_name": character_name})
        return data.get("ocid", "")


def first_list_value(data: dict[str, Any], keys: list[str]) -> list[Any] | None:
    for key in keys:
        value = data.get(key)
        if isinstance(value, list):
            return value
    return None


def extract_character_list(data: dict[str, Any]) -> list[dict[str, Any]]:
    raw_characters = first_list_value(data, ["character_list", "characters"])
    if raw_characters is not None:
        return [item for item in raw_characters if isinstance(item, dict)]

    accounts = first_list_value(data, ["account_list"])
    if accounts is None:
        return []

    characters = []
    for account in accounts:
        if not isinstance(account, dict):
            continue
        account_characters = first_list_value(account, ["character_list", "characters"])
        if account_characters:
            characters.extend(item for item in account_characters if isinstance(item, dict))
    return characters


def normalize_character(raw_character: dict[str, Any]) -> dict[str, Any]:
    return {
        "ocid": raw_character.get("ocid", ""),
        "character_name": raw_character.get("character_name", ""),
        "world_name": raw_character.get("world_name", ""),
        "character_class": raw_character.get("character_class", ""),
        "character_class_level": raw_character.get("character_class_level", ""),
        "character_level": raw_character.get("character_level"),
    }

import requests
from django.conf import settings


class NexonApiError(Exception):
    pass


class NexonClient:
    def __init__(self, api_key=None, base_url=None, timeout=None):
        self.api_key = api_key if api_key is not None else settings.NEXON_API_KEY
        self.base_url = (base_url or settings.NEXON_API_BASE_URL).rstrip("/")
        self.timeout = timeout or settings.NEXON_API_TIMEOUT_SECONDS

    def request(self, path, params=None):
        if not self.api_key:
            raise NexonApiError("NEXON_API_KEY is not configured")

        response = requests.get(
            f"{self.base_url}{path}",
            params=params or {},
            headers={"x-nxopen-api-key": self.api_key},
            timeout=self.timeout,
        )
        if response.status_code >= 400:
            raise NexonApiError(f"Nexon API failed: {response.status_code} {response.text}")
        return response.json()

    def character_list(self):
        return self.request("/maplestory/v1/character/list")

    def ocid(self, character_name):
        return self.request("/maplestory/v1/id", {"character_name": character_name})

    def character_basic(self, ocid, date=None):
        params = {"ocid": ocid}
        if date:
            params["date"] = date
        return self.request("/maplestory/v1/character/basic", params)

    def scheduler(self, ocid, date=None):
        params = {"ocid": ocid}
        if date:
            params["date"] = date
        return self.request("/maplestory/v1/scheduler/character-state", params)

    def notice_list(self):
        return self.request("/maplestory/v1/notice")

    def event_list(self):
        return self.request("/maplestory/v1/notice-event")

    def event_detail(self, event_notice_id):
        return self.request(
            "/maplestory/v1/notice-event/detail",
            {"notice_id": event_notice_id},
        )

    def cashshop_list(self):
        return self.request("/maplestory/v1/notice-cashshop")

    def update_list(self):
        return self.request("/maplestory/v1/notice-update")

    def current_notices(self):
        return {
            "notice": self.notice_list(),
            "event": self.event_list(),
            "cashshop": self.cashshop_list(),
            "update": self.update_list(),
        }

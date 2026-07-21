from django.core.cache import cache
from django.db import transaction
from django.http import JsonResponse
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import NoticeSnapshot, SelectedCharacter
from .nexon import NexonApiError, NexonClient
from .serializers import NoticeSnapshotSerializer, SelectedCharacterSerializer
from .services import (
    check_new_notices,
    collect_current_notice_items,
    collect_latest_closed_sunday_event,
    run_reminder_check,
    update_character_from_basic,
)


SCHEDULER_CACHE_SECONDS = 30
CHARACTER_LIST_CACHE_SECONDS = 600
CURRENT_NOTICES_CACHE_SECONDS = 300
LATEST_SUNDAY_CACHE_SECONDS = 21600


def cached_response(cache_key, timeout, force_refresh, fetch):
    if not force_refresh:
        cached_value = cache.get(cache_key)
        if cached_value is not None:
            return cached_value

    value = fetch()
    cache.set(cache_key, value, timeout=timeout)
    return value


def health(request):
    return JsonResponse({"status": "ok"})


class SelectedCharacterViewSet(viewsets.ModelViewSet):
    queryset = SelectedCharacter.objects.all()
    serializer_class = SelectedCharacterSerializer

    def create(self, request, *args, **kwargs):
        data = request.data.copy()
        client = NexonClient()

        try:
            if not data.get("ocid") and data.get("character_name"):
                ocid_payload = client.ocid(data["character_name"])
                data["ocid"] = ocid_payload.get("ocid")

            if data.get("ocid"):
                basic = client.character_basic(data["ocid"])
                data.setdefault("character_name", basic.get("character_name", ""))
                data.setdefault("world_name", basic.get("world_name", ""))
                data.setdefault("character_class", basic.get("character_class", ""))
                data.setdefault("character_level", basic.get("character_level"))
                data.setdefault("character_image", basic.get("character_image", ""))
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

        serializer = self.get_serializer(data=data)
        serializer.is_valid(raise_exception=True)
        character, _ = SelectedCharacter.objects.update_or_create(
            ocid=serializer.validated_data["ocid"],
            defaults=serializer.validated_data,
        )
        return Response(self.get_serializer(character).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="refresh")
    def refresh(self, request, pk=None):
        character = self.get_object()
        try:
            basic = NexonClient().character_basic(character.ocid)
            update_character_from_basic(character, basic)
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)
        return Response(self.get_serializer(character).data)


class NoticeSnapshotViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = NoticeSnapshot.objects.all()
    serializer_class = NoticeSnapshotSerializer


class NexonCharactersView(APIView):
    def get(self, request):
        try:
            payload = cached_response(
                "nexon:character-list",
                CHARACTER_LIST_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: NexonClient().character_list(),
            )
            return Response(payload)
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class NexonOcidView(APIView):
    def get(self, request):
        character_name = request.query_params.get("character_name")
        if not character_name:
            return Response({"detail": "character_name is required"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            return Response(NexonClient().ocid(character_name))
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class NexonBasicView(APIView):
    def get(self, request, ocid):
        try:
            return Response(NexonClient().character_basic(ocid, date=request.query_params.get("date")))
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class NexonSchedulerView(APIView):
    def get(self, request, ocid):
        try:
            date = request.query_params.get("date")
            cache_key = f"nexon:scheduler:{ocid}:{date or 'today'}"
            payload = cached_response(
                cache_key,
                SCHEDULER_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: NexonClient().scheduler(ocid, date=date),
            )
            return Response(payload)
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class CurrentNoticesView(APIView):
    def get(self, request):
        try:
            items = cached_response(
                "nexon:current-notices",
                CURRENT_NOTICES_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                collect_current_notice_items,
            )
            return Response({"items": items})
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class LatestSundayEventView(APIView):
    def get(self, request):
        try:
            event = cached_response(
                "nexon:latest-sunday-event",
                LATEST_SUNDAY_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                collect_latest_closed_sunday_event,
            )
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

        if event is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(event)


class CheckNewNoticesView(APIView):
    @transaction.atomic
    def post(self, request):
        try:
            return Response(check_new_notices())
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class ReminderCheckView(APIView):
    mode = None

    def post(self, request):
        try:
            result = run_reminder_check(
                self.mode,
                ocid=request.data.get("ocid"),
                date=request.data.get("date"),
                force=bool(request.data.get("force", False)),
            )
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)
        return Response(result)


class DailyReminderCheckView(ReminderCheckView):
    mode = "daily"


class WeeklyReminderCheckView(ReminderCheckView):
    mode = "weekly"


class LauncherExitReminderCheckView(ReminderCheckView):
    mode = "launcher_exit"

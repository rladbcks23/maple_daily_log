from django.core.cache import cache
from django.db import transaction
from django.http import JsonResponse
from rest_framework import status, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import NoticeSnapshot, SundayEventSnapshot
from .nexon import NexonApiError, NexonClient
from .serializers import NoticeSnapshotSerializer, SundayEventSnapshotSerializer
from .services import (
    check_new_notices,
    collect_or_load_latest_sunday_event,
    collect_current_notice_items,
    run_reminder_check,
)


SCHEDULER_CACHE_SECONDS = 30
CHARACTER_LIST_CACHE_SECONDS = 600
CHARACTER_BASIC_CACHE_SECONDS = 86400
CURRENT_NOTICES_CACHE_SECONDS = 300

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


class NoticeSnapshotViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = NoticeSnapshot.objects.all()
    serializer_class = NoticeSnapshotSerializer


class SundayEventSnapshotViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = SundayEventSnapshot.objects.all()
    serializer_class = SundayEventSnapshotSerializer


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
            date = request.query_params.get("date")
            cache_key = f"nexon:character-basic:{ocid}:{date or 'today'}"
            payload = cached_response(
                cache_key,
                CHARACTER_BASIC_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: NexonClient().character_basic(ocid, date=date),
            )
            return Response(payload)
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
            event = collect_or_load_latest_sunday_event(
                force_refresh=request.query_params.get("refresh") == "1",
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

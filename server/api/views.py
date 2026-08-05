import hashlib

from django.core.cache import cache
from django.conf import settings
from django.db import transaction
from django.http import JsonResponse
from rest_framework import status, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import NoticeSnapshot, SundayEventSnapshot
from .nexon import NexonApiError, NexonClient
from .serializers import NoticeSnapshotSerializer, SundayEventSnapshotSerializer
from .services import (
    active_notice_items_from_db,
    check_new_notices,
    collect_and_store_notice_items,
    collect_or_load_latest_sunday_event,
)


SCHEDULER_CACHE_SECONDS = 30
CHARACTER_LIST_CACHE_SECONDS = 600
CHARACTER_BASIC_CACHE_SECONDS = 86400
def nexon_api_key_from_request(request):
    return (
        request.headers.get("X-Nexon-Api-Key")
        or request.headers.get("x-nxopen-api-key")
        or request.query_params.get("nexon_api_key")
        or None
    )


def nexon_cache_scope(request):
    api_key = nexon_api_key_from_request(request)
    if not api_key:
        return "server"
    return hashlib.sha256(api_key.encode("utf-8")).hexdigest()[:16]


def nexon_client_from_request(request):
    return NexonClient(api_key=nexon_api_key_from_request(request))


def nexon_user_client_from_request(request):
    api_key = nexon_api_key_from_request(request)
    if not api_key:
        raise NexonApiError("Nexon API key is required")
    return NexonClient(api_key=api_key)


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
                f"nexon:{nexon_cache_scope(request)}:character-list",
                CHARACTER_LIST_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: nexon_user_client_from_request(request).character_list(),
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
            return Response(nexon_user_client_from_request(request).ocid(character_name))
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class NexonBasicView(APIView):
    def get(self, request, ocid):
        try:
            date = request.query_params.get("date")
            cache_key = f"nexon:{nexon_cache_scope(request)}:character-basic:{ocid}:{date or 'today'}"
            payload = cached_response(
                cache_key,
                CHARACTER_BASIC_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: nexon_user_client_from_request(request).character_basic(ocid, date=date),
            )
            return Response(payload)
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class NexonSchedulerView(APIView):
    def get(self, request, ocid):
        try:
            date = request.query_params.get("date")
            cache_key = f"nexon:{nexon_cache_scope(request)}:scheduler:{ocid}:{date or 'today'}"
            payload = cached_response(
                cache_key,
                SCHEDULER_CACHE_SECONDS,
                request.query_params.get("refresh") == "1",
                lambda: nexon_user_client_from_request(request).scheduler(ocid, date=date),
            )
            return Response(payload)
        except NexonApiError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class CurrentNoticesView(APIView):
    def get(self, request):
        try:
            force_refresh = request.query_params.get("refresh") == "1"
            if force_refresh or not NoticeSnapshot.objects.filter(is_active=True).exists():
                items = collect_and_store_notice_items()["items"]
            else:
                items = active_notice_items_from_db()
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


class AppVersionView(APIView):
    def get(self, request):
        return Response(
            {
                "version": settings.APP_LATEST_VERSION,
                "downloadUrl": settings.APP_DOWNLOAD_URL,
                "notes": settings.APP_RELEASE_NOTES,
            }
        )

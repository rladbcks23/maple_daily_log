from datetime import datetime
from zoneinfo import ZoneInfo

from django.conf import settings
from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from api import repositories
from api.nexon import NexonApiClient, NexonApiError
from api.serializers import SnapshotRequestSerializer


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def health(_request):
    return Response({"status": "ok"})


@api_view(["POST"])
def sync_characters(_request):
    try:
        characters = NexonApiClient().fetch_character_list()
        with transaction.atomic():
            saved = repositories.upsert_characters(characters)
    except NexonApiError as exc:
        return Response({"status": "error", "code": "nexon_api_error", "message": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    return Response(
        {
            "status": "saved",
            "found": len(characters),
            "saved": saved,
            "message": "Nexon account characters were synchronized into characters.",
        }
    )


@api_view(["POST"])
def sync_snapshot(request):
    serializer = SnapshotRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    data = serializer.validated_data
    snapshot_type = data.get("snapshotType") or "force_refresh"
    play_date = data.get("playDate") or datetime.now(ZoneInfo(settings.MAPLE["TIMEZONE"])).date()

    try:
        bundle = NexonApiClient().fetch_snapshot_bundle(data["ocid"])
        with transaction.atomic():
            saved_snapshot = repositories.save_snapshot(bundle, snapshot_type, play_date)
    except NexonApiError as exc:
        return Response({"status": "error", "code": "nexon_api_error", "message": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    return Response(
        {
            "status": "saved",
            "ocid": data["ocid"],
            "characterId": saved_snapshot["characterId"],
            "snapshotId": saved_snapshot["snapshotId"],
            "characterName": saved_snapshot["characterName"],
            "characterLevel": saved_snapshot["characterLevel"],
            "snapshotType": snapshot_type,
            "playDate": saved_snapshot["playDate"],
            "apiCallsUsed": bundle.api_calls_used,
            "sections": list(bundle.sections.keys()),
            "message": "Nexon API data was fetched and saved into character_snapshots.",
        }
    )


@api_view(["GET"])
def list_characters(_request):
    return Response({"characters": repositories.list_characters()})


@api_view(["GET"])
def latest_snapshot(_request, character_id):
    snapshot = repositories.latest_snapshot(character_id)
    if snapshot is None:
        return Response(
            {"status": "not_found", "message": "No snapshot exists for this character."},
            status=status.HTTP_404_NOT_FOUND,
        )
    return Response(snapshot)


@api_view(["POST"])
def create_daily_report(request):
    return Response(
        {
            "status": "planned",
            "message": "Daily report calculation will be implemented after snapshot comparison rules are finalized.",
        },
        status=status.HTTP_202_ACCEPTED,
    )

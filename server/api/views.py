from datetime import date

from django.shortcuts import get_object_or_404
from django.utils.dateparse import parse_date, parse_datetime
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .models import Character, CharacterSnapshot, PlaySession, Report
from .nexon import NEXON_ENDPOINTS, SNAPSHOT_BUNDLES
from .serializers import CharacterSerializer, CharacterSnapshotSerializer, PlaySessionSerializer, ReportSerializer
from .services import create_report, end_play_session, find_missing_scheduler_tasks, latest_snapshot_for_date, start_play_session, sync_characters_from_nexon, today_play_date


@api_view(["GET"])
def nexon_endpoints(_request):
    return Response({"endpoints": NEXON_ENDPOINTS})


@api_view(["GET"])
def snapshot_bundles(_request):
    return Response({"bundles": SNAPSHOT_BUNDLES})


@api_view(["GET", "POST"])
def sync_characters(request):
    if request.method == "GET":
        return Response(
            {
                "detail": "POST 요청을 보내면 .env의 NEXON_API_KEY로 캐릭터 목록을 동기화한다.",
                "method": "POST",
                "url": "/api/sync/characters",
            }
        )

    sync_result = sync_characters_from_nexon()
    return Response(
        {
            "created": sync_result["created"],
            "updated": sync_result["updated"],
            "total": sync_result["total"],
            "characters": CharacterSerializer(sync_result["characters"], many=True).data,
        }
    )


@api_view(["GET", "POST"])
def characters(request):
    if request.method == "GET":
        queryset = Character.objects.all()
        return Response(CharacterSerializer(queryset, many=True).data)

    serializer = CharacterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    character = serializer.save()
    return Response(CharacterSerializer(character).data, status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH"])
def character_detail(request, character_id):
    character = get_object_or_404(Character, id=character_id)
    if request.method == "GET":
        return Response(CharacterSerializer(character).data)

    serializer = CharacterSerializer(character, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response(serializer.data)


@api_view(["POST"])
def create_snapshot(request):
    serializer = CharacterSnapshotSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    snapshot = serializer.save()
    return Response(CharacterSnapshotSerializer(snapshot).data, status=status.HTTP_201_CREATED)


@api_view(["GET"])
def latest_snapshot(request):
    character_id = request.query_params.get("character_id")
    if not character_id:
        return Response({"detail": "character_id is required"}, status=status.HTTP_400_BAD_REQUEST)
    play_date_value = parse_date(request.query_params.get("play_date", "")) if request.query_params.get("play_date") else None
    character = get_object_or_404(Character, id=character_id)
    snapshot = (
        latest_snapshot_for_date(character, play_date_value)
        if play_date_value
        else CharacterSnapshot.objects.filter(character=character).order_by("-play_date", "-recorded_at").first()
    )
    if not snapshot:
        return Response({"detail": "snapshot not found"}, status=status.HTTP_404_NOT_FOUND)
    return Response(CharacterSnapshotSerializer(snapshot).data)


@api_view(["POST"])
def start_session(request):
    character = None
    if request.data.get("character"):
        character = get_object_or_404(Character, id=request.data["character"])
    play_date_value = parse_date(request.data.get("play_date", "")) or today_play_date()
    started_at = parse_datetime(request.data.get("started_at", "")) if request.data.get("started_at") else timezone.now()
    start_snapshot = None
    if request.data.get("start_snapshot"):
        start_snapshot = get_object_or_404(CharacterSnapshot, id=request.data["start_snapshot"])

    session = start_play_session(
        character=character,
        play_date=play_date_value,
        started_at=started_at,
        start_snapshot=start_snapshot,
    )
    return Response(PlaySessionSerializer(session).data, status=status.HTTP_201_CREATED)


@api_view(["POST"])
def end_session(request, session_id):
    session = get_object_or_404(PlaySession, id=session_id)
    ended_at = parse_datetime(request.data.get("ended_at", "")) if request.data.get("ended_at") else timezone.now()
    end_snapshot = None
    if request.data.get("end_snapshot"):
        end_snapshot = get_object_or_404(CharacterSnapshot, id=request.data["end_snapshot"])

    session = end_play_session(session=session, ended_at=ended_at, end_snapshot=end_snapshot)
    response = PlaySessionSerializer(session).data
    if session.end_snapshot:
        response["missing_tasks"] = find_missing_scheduler_tasks(session.end_snapshot)
    return Response(response)


@api_view(["POST"])
def generate_report(request, report_type):
    if report_type not in Report.ReportType.values:
        return Response({"detail": "unsupported report_type"}, status=status.HTTP_400_BAD_REQUEST)

    report_date = parse_date(request.data.get("report_date", "")) or today_play_date()
    character_ids = request.data.get("character_ids")
    characters_query = Character.objects.filter(is_ignored=False)
    if character_ids:
        characters_query = characters_query.filter(id__in=character_ids)

    reports = [
        create_report(character=character, report_type=report_type, report_date=report_date)
        for character in characters_query
    ]
    return Response(ReportSerializer(reports, many=True).data, status=status.HTTP_201_CREATED)


@api_view(["GET"])
def reports(request):
    queryset = Report.objects.all()
    if request.query_params.get("character_id"):
        queryset = queryset.filter(character_id=request.query_params["character_id"])
    if request.query_params.get("report_type"):
        queryset = queryset.filter(report_type=request.query_params["report_type"])
    return Response(ReportSerializer(queryset, many=True).data)


@api_view(["GET"])
def missing_tasks(request):
    character_id = request.query_params.get("character_id")
    if not character_id:
        return Response({"detail": "character_id is required"}, status=status.HTTP_400_BAD_REQUEST)
    play_date_value = parse_date(request.query_params.get("play_date", "")) or date.today()
    character = get_object_or_404(Character, id=character_id)
    snapshot = latest_snapshot_for_date(character, play_date_value)
    return Response(
        {
            "character_id": character_id,
            "play_date": play_date_value,
            "missing_tasks": find_missing_scheduler_tasks(snapshot),
        }
    )

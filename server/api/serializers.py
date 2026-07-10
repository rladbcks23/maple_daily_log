from rest_framework import serializers

from .models import Character, CharacterSnapshot, PlaySession, Report, SchedulerNotification


class CharacterSerializer(serializers.ModelSerializer):
    class Meta:
        model = Character
        fields = [
            "id",
            "ocid",
            "character_name",
            "world_name",
            "character_class",
            "character_class_level",
            "character_level",
            "tags",
            "is_ignored",
            "last_synced_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "last_synced_at", "created_at", "updated_at"]


class CharacterSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = CharacterSnapshot
        fields = [
            "id",
            "character",
            "snapshot_type",
            "bundle_name",
            "play_date",
            "recorded_at",
            "character_level",
            "character_exp",
            "exp_rate",
            "combat_power",
            "snapshot_json",
            "created_at",
        ]
        read_only_fields = ["id", "recorded_at", "created_at"]


class PlaySessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlaySession
        fields = [
            "id",
            "character",
            "play_date",
            "started_at",
            "ended_at",
            "play_minutes",
            "source",
            "status",
            "start_snapshot",
            "end_snapshot",
            "note",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "play_minutes", "status", "created_at", "updated_at"]


class ReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = Report
        fields = [
            "id",
            "character",
            "report_type",
            "report_date",
            "period_start",
            "period_end",
            "start_snapshot",
            "end_snapshot",
            "first_started_at",
            "play_minutes",
            "level_delta",
            "exp_delta",
            "combat_power_delta",
            "summary_json",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class SchedulerNotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = SchedulerNotification
        fields = [
            "id",
            "character",
            "notification_type",
            "scheduled_for",
            "status",
            "payload_json",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

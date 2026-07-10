from rest_framework import serializers

from .models import CHARACTER_TAGS, Character, CharacterSnapshot, PlaySession, Report, SchedulerNotification


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


class CharacterTagsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Character
        fields = ["id", "character_name", "tags", "is_ignored"]
        read_only_fields = ["id", "character_name"]

    def validate_tags(self, tags):
        if not isinstance(tags, list):
            raise serializers.ValidationError("tags must be a list")
        invalid_tags = [tag for tag in tags if tag not in CHARACTER_TAGS]
        if invalid_tags:
            raise serializers.ValidationError(f"unsupported tags: {invalid_tags}")
        if len(tags) != len(set(tags)):
            raise serializers.ValidationError("tags must not contain duplicates")
        return tags


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

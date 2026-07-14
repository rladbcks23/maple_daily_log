from rest_framework import serializers

from .models import NoticeSnapshot, SelectedCharacter


class SelectedCharacterSerializer(serializers.ModelSerializer):
    class Meta:
        model = SelectedCharacter
        fields = [
            "id",
            "character_name",
            "world_name",
            "ocid",
            "character_class",
            "character_level",
            "character_image",
            "selected_at",
            "updated_at",
        ]
        read_only_fields = ["id", "selected_at", "updated_at"]


class NoticeSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = NoticeSnapshot
        fields = [
            "id",
            "notice_type",
            "notice_id",
            "title",
            "link",
            "registered_at",
            "collected_at",
        ]
        read_only_fields = ["id", "collected_at"]

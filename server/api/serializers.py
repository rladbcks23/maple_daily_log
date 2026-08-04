from rest_framework import serializers

from .models import NoticeSnapshot, SundayEventSnapshot


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
            "thumbnail",
            "event_start_at",
            "event_end_at",
            "sale_start_at",
            "sale_end_at",
            "sale_ongoing",
            "content",
            "content_image_urls",
            "is_active",
            "ended_notified",
            "first_seen_at",
            "collected_at",
        ]
        read_only_fields = ["id", "first_seen_at", "collected_at"]


class SundayEventSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = SundayEventSnapshot
        fields = [
            "id",
            "notice_id",
            "title",
            "link",
            "registered_at",
            "thumbnail",
            "event_start_at",
            "event_end_at",
            "content",
            "content_image_urls",
            "collected_at",
        ]
        read_only_fields = ["id", "collected_at"]

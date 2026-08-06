from django.conf import settings
from rest_framework import serializers

from .models import Feedback, NoticeSnapshot, SundayEventSnapshot


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


class FeedbackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feedback
        fields = ["id", "content", "attachment", "app_version", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_content(self, value):
        if not value.strip():
            raise serializers.ValidationError("내용을 입력해주세요.")
        return value.strip()

    def validate_attachment(self, value):
        if value is None:
            return value
        if value.size > settings.FEEDBACK_ATTACHMENT_MAX_BYTES:
            limit_mb = settings.FEEDBACK_ATTACHMENT_MAX_BYTES // (1024 * 1024)
            raise serializers.ValidationError(f"첨부파일은 {limit_mb}MB 이하만 가능합니다.")
        content_type = (value.content_type or "").lower()
        if not (content_type.startswith("image/") or content_type.startswith("video/")):
            raise serializers.ValidationError("이미지 또는 영상 파일만 첨부할 수 있습니다.")
        return value


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

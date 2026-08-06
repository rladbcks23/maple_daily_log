from django.contrib import admin

from .models import Feedback, NoticeSnapshot, SundayEventSnapshot


@admin.register(Feedback)
class FeedbackAdmin(admin.ModelAdmin):
    list_display = ("__str__", "attachment", "app_version", "is_resolved", "created_at")
    list_filter = ("is_resolved", "app_version")
    search_fields = ("content",)
    list_editable = ("is_resolved",)


@admin.register(NoticeSnapshot)
class NoticeSnapshotAdmin(admin.ModelAdmin):
    list_display = ("notice_type", "title", "registered_at", "collected_at")
    list_filter = ("notice_type",)
    search_fields = ("title", "notice_id")


@admin.register(SundayEventSnapshot)
class SundayEventSnapshotAdmin(admin.ModelAdmin):
    list_display = ("title", "event_start_at", "event_end_at", "collected_at")
    search_fields = ("title", "notice_id")

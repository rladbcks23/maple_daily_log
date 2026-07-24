from django.contrib import admin

from .models import NoticeSnapshot, SundayEventSnapshot


@admin.register(NoticeSnapshot)
class NoticeSnapshotAdmin(admin.ModelAdmin):
    list_display = ("notice_type", "title", "registered_at", "collected_at")
    list_filter = ("notice_type",)
    search_fields = ("title", "notice_id")


@admin.register(SundayEventSnapshot)
class SundayEventSnapshotAdmin(admin.ModelAdmin):
    list_display = ("title", "event_start_at", "event_end_at", "collected_at")
    search_fields = ("title", "notice_id")

from django.contrib import admin

from .models import NoticeSnapshot, SelectedCharacter


@admin.register(SelectedCharacter)
class SelectedCharacterAdmin(admin.ModelAdmin):
    list_display = ("character_name", "world_name", "character_class", "character_level", "updated_at")
    search_fields = ("character_name", "world_name", "ocid")


@admin.register(NoticeSnapshot)
class NoticeSnapshotAdmin(admin.ModelAdmin):
    list_display = ("notice_type", "title", "registered_at", "collected_at")
    list_filter = ("notice_type",)
    search_fields = ("title", "notice_id")

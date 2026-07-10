import uuid

from django.db import models


def default_character_tags():
    return ["ignored"]


class Character(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ocid = models.CharField(max_length=128, unique=True)
    character_name = models.CharField(max_length=128)
    world_name = models.CharField(max_length=64, blank=True)
    character_class = models.CharField(max_length=64, blank=True)
    character_class_level = models.CharField(max_length=64, blank=True)
    character_level = models.IntegerField(null=True, blank=True)
    tags = models.JSONField(default=default_character_tags, blank=True)
    is_ignored = models.BooleanField(default=False)
    last_synced_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["world_name", "character_name"]

    def __str__(self):
        return f"{self.character_name} ({self.world_name})"


class CharacterSnapshot(models.Model):
    class SnapshotType(models.TextChoices):
        APP_START = "app_start", "App start"
        GAME_START = "game_start", "Game start"
        GAME_END = "game_end", "Game end"
        MAPLE_LAUNCHER_START = "maple_launcher_start", "Maple launcher start"
        MAPLE_LAUNCHER_END = "maple_launcher_end", "Maple launcher end"
        FORCE_REFRESH = "force_refresh", "Force refresh"
        HOURLY_AUTO = "hourly_auto", "Hourly auto"
        MANUAL = "manual", "Manual"
        SCHEDULED = "scheduled", "Scheduled"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    character = models.ForeignKey(Character, on_delete=models.CASCADE, related_name="snapshots")
    snapshot_type = models.CharField(max_length=32, choices=SnapshotType.choices, default=SnapshotType.MANUAL)
    bundle_name = models.CharField(max_length=32, blank=True)
    play_date = models.DateField()
    recorded_at = models.DateTimeField(auto_now_add=True)
    character_level = models.IntegerField(null=True, blank=True)
    character_exp = models.CharField(max_length=64, blank=True)
    exp_rate = models.CharField(max_length=64, blank=True)
    combat_power = models.CharField(max_length=64, blank=True)
    snapshot_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["character", "play_date", "-recorded_at"]),
            models.Index(fields=["snapshot_type", "play_date"]),
        ]
        ordering = ["-recorded_at"]


class PlaySession(models.Model):
    class Source(models.TextChoices):
        LOCAL_APP = "local_app", "Local app"
        MANUAL = "manual", "Manual"
        ESTIMATED = "estimated", "Estimated"

    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        ENDED = "ended", "Ended"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    character = models.ForeignKey(Character, on_delete=models.SET_NULL, null=True, blank=True, related_name="play_sessions")
    play_date = models.DateField()
    started_at = models.DateTimeField()
    ended_at = models.DateTimeField(null=True, blank=True)
    play_minutes = models.IntegerField(default=0)
    source = models.CharField(max_length=32, choices=Source.choices, default=Source.LOCAL_APP)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.RUNNING)
    start_snapshot = models.ForeignKey(CharacterSnapshot, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    end_snapshot = models.ForeignKey(CharacterSnapshot, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["character", "play_date"]),
            models.Index(fields=["status", "started_at"]),
        ]
        ordering = ["-started_at"]


class Report(models.Model):
    class ReportType(models.TextChoices):
        DAILY = "daily", "Daily"
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    character = models.ForeignKey(Character, on_delete=models.SET_NULL, null=True, blank=True, related_name="reports")
    report_type = models.CharField(max_length=16, choices=ReportType.choices)
    report_date = models.DateField()
    period_start = models.DateField()
    period_end = models.DateField()
    start_snapshot = models.ForeignKey(CharacterSnapshot, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    end_snapshot = models.ForeignKey(CharacterSnapshot, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    first_started_at = models.DateTimeField(null=True, blank=True)
    play_minutes = models.IntegerField(default=0)
    level_delta = models.IntegerField(null=True, blank=True)
    exp_delta = models.CharField(max_length=64, blank=True)
    combat_power_delta = models.CharField(max_length=64, blank=True)
    summary_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["character", "report_type", "report_date"], name="unique_character_report_period")
        ]
        indexes = [
            models.Index(fields=["character", "report_type", "-report_date"]),
        ]
        ordering = ["-report_date", "character__character_name"]


class SchedulerNotification(models.Model):
    class NotificationType(models.TextChoices):
        WEEKLY_QUEST_REMINDER = "weekly_quest_reminder", "Weekly quest reminder"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        SENT = "sent", "Sent"
        SKIPPED = "skipped", "Skipped"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    character = models.ForeignKey(Character, on_delete=models.SET_NULL, null=True, blank=True, related_name="notifications")
    notification_type = models.CharField(max_length=32, choices=NotificationType.choices)
    scheduled_for = models.DateTimeField()
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    payload_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["status", "scheduled_for"]),
        ]

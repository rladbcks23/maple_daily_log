# Generated manually for the rebuilt planning-first server.

import django.db.models.deletion
import uuid
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="Character",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("ocid", models.CharField(max_length=128, unique=True)),
                ("character_name", models.CharField(max_length=128)),
                ("world_name", models.CharField(blank=True, max_length=64)),
                ("character_class", models.CharField(blank=True, max_length=64)),
                ("character_class_level", models.CharField(blank=True, max_length=64)),
                ("character_level", models.IntegerField(blank=True, null=True)),
                ("tags", models.JSONField(blank=True, default=list)),
                ("is_ignored", models.BooleanField(default=False)),
                ("last_synced_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={"ordering": ["world_name", "character_name"]},
        ),
        migrations.CreateModel(
            name="CharacterSnapshot",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("snapshot_type", models.CharField(choices=[("app_start", "App start"), ("game_start", "Game start"), ("game_end", "Game end"), ("force_refresh", "Force refresh"), ("manual", "Manual"), ("scheduled", "Scheduled")], default="manual", max_length=32)),
                ("bundle_name", models.CharField(blank=True, max_length=32)),
                ("play_date", models.DateField()),
                ("recorded_at", models.DateTimeField(auto_now_add=True)),
                ("character_level", models.IntegerField(blank=True, null=True)),
                ("character_exp", models.CharField(blank=True, max_length=64)),
                ("exp_rate", models.CharField(blank=True, max_length=64)),
                ("combat_power", models.CharField(blank=True, max_length=64)),
                ("snapshot_json", models.JSONField(default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("character", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="snapshots", to="api.character")),
            ],
            options={
                "ordering": ["-recorded_at"],
                "indexes": [
                    models.Index(fields=["character", "play_date", "-recorded_at"], name="api_charact_charact_0421f5_idx"),
                    models.Index(fields=["snapshot_type", "play_date"], name="api_charact_snapsho_5e8522_idx"),
                ],
            },
        ),
        migrations.CreateModel(
            name="PlaySession",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("play_date", models.DateField()),
                ("started_at", models.DateTimeField()),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("play_minutes", models.IntegerField(default=0)),
                ("source", models.CharField(choices=[("local_app", "Local app"), ("manual", "Manual"), ("estimated", "Estimated")], default="local_app", max_length=32)),
                ("status", models.CharField(choices=[("running", "Running"), ("ended", "Ended")], default="running", max_length=16)),
                ("note", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("character", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="play_sessions", to="api.character")),
                ("end_snapshot", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="+", to="api.charactersnapshot")),
                ("start_snapshot", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="+", to="api.charactersnapshot")),
            ],
            options={
                "ordering": ["-started_at"],
                "indexes": [
                    models.Index(fields=["character", "play_date"], name="api_playses_charact_33e28d_idx"),
                    models.Index(fields=["status", "started_at"], name="api_playses_status_5fc7bc_idx"),
                ],
            },
        ),
        migrations.CreateModel(
            name="Report",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("report_type", models.CharField(choices=[("daily", "Daily"), ("weekly", "Weekly"), ("monthly", "Monthly")], max_length=16)),
                ("report_date", models.DateField()),
                ("period_start", models.DateField()),
                ("period_end", models.DateField()),
                ("first_started_at", models.DateTimeField(blank=True, null=True)),
                ("play_minutes", models.IntegerField(default=0)),
                ("level_delta", models.IntegerField(blank=True, null=True)),
                ("exp_delta", models.CharField(blank=True, max_length=64)),
                ("combat_power_delta", models.CharField(blank=True, max_length=64)),
                ("summary_json", models.JSONField(default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("character", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="reports", to="api.character")),
                ("end_snapshot", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="+", to="api.charactersnapshot")),
                ("start_snapshot", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="+", to="api.charactersnapshot")),
            ],
            options={
                "ordering": ["-report_date", "character__character_name"],
                "indexes": [
                    models.Index(fields=["character", "report_type", "-report_date"], name="api_report_charact_67f12e_idx"),
                ],
            },
        ),
        migrations.CreateModel(
            name="SchedulerNotification",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("notification_type", models.CharField(choices=[("weekly_quest_reminder", "Weekly quest reminder")], max_length=32)),
                ("scheduled_for", models.DateTimeField()),
                ("status", models.CharField(choices=[("pending", "Pending"), ("sent", "Sent"), ("skipped", "Skipped")], default="pending", max_length=16)),
                ("payload_json", models.JSONField(default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("character", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="notifications", to="api.character")),
            ],
            options={
                "indexes": [
                    models.Index(fields=["status", "scheduled_for"], name="api_schedul_status_575623_idx"),
                ],
            },
        ),
        migrations.AddConstraint(
            model_name="report",
            constraint=models.UniqueConstraint(fields=("character", "report_type", "report_date"), name="unique_character_report_period"),
        ),
    ]

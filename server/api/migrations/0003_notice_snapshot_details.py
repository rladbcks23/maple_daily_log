from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("api", "0002_sunday_event_snapshot_remove_selected_character"),
    ]

    operations = [
        migrations.AddField(
            model_name="noticesnapshot",
            name="thumbnail",
            field=models.URLField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="event_start_at",
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="event_end_at",
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="sale_start_at",
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="sale_end_at",
            field=models.CharField(blank=True, max_length=40),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="sale_ongoing",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="content",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="content_image_urls",
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="is_active",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="ended_notified",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="first_seen_at",
            field=models.DateTimeField(auto_now_add=True),
        ),
        migrations.AddField(
            model_name="noticesnapshot",
            name="collected_at",
            field=models.DateTimeField(auto_now=True),
        ),
    ]

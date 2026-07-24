from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("api", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="SundayEventSnapshot",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("notice_id", models.CharField(max_length=120, unique=True)),
                ("title", models.CharField(max_length=300)),
                ("link", models.URLField(blank=True, max_length=500)),
                ("registered_at", models.CharField(blank=True, max_length=40)),
                ("thumbnail", models.URLField(blank=True, max_length=500)),
                ("event_start_at", models.CharField(blank=True, max_length=40)),
                ("event_end_at", models.CharField(blank=True, max_length=40)),
                ("content", models.TextField(blank=True)),
                ("content_image_urls", models.JSONField(blank=True, default=list)),
                ("collected_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "ordering": ["-event_start_at", "-registered_at", "title"],
            },
        ),
        migrations.DeleteModel(
            name="SelectedCharacter",
        ),
    ]

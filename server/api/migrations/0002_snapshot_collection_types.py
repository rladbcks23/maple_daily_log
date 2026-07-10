from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("api", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="charactersnapshot",
            name="snapshot_type",
            field=models.CharField(
                choices=[
                    ("app_start", "App start"),
                    ("game_start", "Game start"),
                    ("game_end", "Game end"),
                    ("maple_launcher_start", "Maple launcher start"),
                    ("maple_launcher_end", "Maple launcher end"),
                    ("force_refresh", "Force refresh"),
                    ("hourly_auto", "Hourly auto"),
                    ("manual", "Manual"),
                    ("scheduled", "Scheduled"),
                ],
                default="manual",
                max_length=32,
            ),
        ),
    ]

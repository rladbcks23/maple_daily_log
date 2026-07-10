from django.db import migrations, models

import api.models


def fill_empty_tags_with_ignored(apps, schema_editor):
    Character = apps.get_model("api", "Character")
    for character in Character.objects.all():
        if not character.tags:
            character.tags = ["ignored"]
            character.save(update_fields=["tags"])


def remove_auto_ignored_from_empty_tags(apps, schema_editor):
    Character = apps.get_model("api", "Character")
    for character in Character.objects.filter(tags=["ignored"]):
        character.tags = []
        character.save(update_fields=["tags"])


class Migration(migrations.Migration):
    dependencies = [
        ("api", "0002_snapshot_collection_types"),
    ]

    operations = [
        migrations.AlterField(
            model_name="character",
            name="tags",
            field=models.JSONField(blank=True, default=api.models.default_character_tags),
        ),
        migrations.RunPython(fill_empty_tags_with_ignored, remove_auto_ignored_from_empty_tags),
    ]

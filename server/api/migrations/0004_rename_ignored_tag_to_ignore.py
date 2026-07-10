from django.db import migrations, models

import api.models


def rename_ignored_tag_to_ignore(apps, schema_editor):
    Character = apps.get_model("api", "Character")
    for character in Character.objects.all():
        tags = character.tags or []
        changed = False
        normalized = []
        for tag in tags:
            if tag == "ignored":
                tag = "ignore"
                changed = True
            if tag not in normalized:
                normalized.append(tag)
        if not normalized:
            normalized = ["ignore"]
            changed = True
        if changed:
            character.tags = normalized
            character.save(update_fields=["tags"])


def rename_ignore_tag_to_ignored(apps, schema_editor):
    Character = apps.get_model("api", "Character")
    for character in Character.objects.all():
        tags = character.tags or []
        changed = False
        normalized = []
        for tag in tags:
            if tag == "ignore":
                tag = "ignored"
                changed = True
            if tag not in normalized:
                normalized.append(tag)
        if changed:
            character.tags = normalized
            character.save(update_fields=["tags"])


class Migration(migrations.Migration):
    dependencies = [
        ("api", "0003_default_ignored_character_tags"),
    ]

    operations = [
        migrations.AlterField(
            model_name="character",
            name="tags",
            field=models.JSONField(blank=True, default=api.models.default_character_tags),
        ),
        migrations.RunPython(rename_ignored_tag_to_ignore, rename_ignore_tag_to_ignored),
    ]

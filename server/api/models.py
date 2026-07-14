from django.db import models


class SelectedCharacter(models.Model):
    character_name = models.CharField(max_length=80)
    world_name = models.CharField(max_length=40, blank=True)
    ocid = models.CharField(max_length=120, unique=True)
    character_class = models.CharField(max_length=80, blank=True)
    character_level = models.PositiveIntegerField(null=True, blank=True)
    character_image = models.URLField(max_length=500, blank=True)
    selected_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["world_name", "character_name"]

    def __str__(self):
        return f"{self.world_name} {self.character_name}".strip()


class NoticeSnapshot(models.Model):
    NOTICE = "notice"
    EVENT = "event"
    CASHSHOP = "cashshop"
    UPDATE = "update"

    NOTICE_TYPE_CHOICES = [
        (NOTICE, "공지사항"),
        (EVENT, "이벤트"),
        (CASHSHOP, "캐시샵"),
        (UPDATE, "업데이트"),
    ]

    notice_type = models.CharField(max_length=20, choices=NOTICE_TYPE_CHOICES)
    notice_id = models.CharField(max_length=120)
    title = models.CharField(max_length=300)
    link = models.URLField(max_length=500, blank=True)
    registered_at = models.CharField(max_length=40, blank=True)
    collected_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["notice_type", "-registered_at", "title"]
        constraints = [
            models.UniqueConstraint(fields=["notice_type", "notice_id"], name="unique_notice_snapshot")
        ]

    def __str__(self):
        return f"[{self.notice_type}] {self.title}"

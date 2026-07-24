from django.db import models


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


class SundayEventSnapshot(models.Model):
    notice_id = models.CharField(max_length=120, unique=True)
    title = models.CharField(max_length=300)
    link = models.URLField(max_length=500, blank=True)
    registered_at = models.CharField(max_length=40, blank=True)
    thumbnail = models.URLField(max_length=500, blank=True)
    event_start_at = models.CharField(max_length=40, blank=True)
    event_end_at = models.CharField(max_length=40, blank=True)
    content = models.TextField(blank=True)
    content_image_urls = models.JSONField(default=list, blank=True)
    collected_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-event_start_at", "-registered_at", "title"]

    def __str__(self):
        return self.title

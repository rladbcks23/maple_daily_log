from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AppVersionView,
    CheckNewNoticesView,
    CurrentNoticesView,
    DailyReminderCheckView,
    LauncherExitReminderCheckView,
    LatestSundayEventView,
    NexonBasicView,
    NexonCharactersView,
    NexonOcidView,
    NexonSchedulerView,
    NoticeSnapshotViewSet,
    SundayEventSnapshotViewSet,
    WeeklyReminderCheckView,
)

router = DefaultRouter()
router.register("notice-snapshots", NoticeSnapshotViewSet, basename="notice-snapshot")
router.register("sunday-events", SundayEventSnapshotViewSet, basename="sunday-event")

urlpatterns = [
    path("", include(router.urls)),
    path("nexon/characters", NexonCharactersView.as_view()),
    path("nexon/ocid", NexonOcidView.as_view()),
    path("nexon/characters/<str:ocid>/basic", NexonBasicView.as_view()),
    path("nexon/scheduler/<str:ocid>", NexonSchedulerView.as_view()),
    path("notices/current", CurrentNoticesView.as_view()),
    path("notices/latest-sunday", LatestSundayEventView.as_view()),
    path("notices/check-new", CheckNewNoticesView.as_view()),
    path("reminders/daily-check", DailyReminderCheckView.as_view()),
    path("reminders/weekly-check", WeeklyReminderCheckView.as_view()),
    path("reminders/launcher-exit-check", LauncherExitReminderCheckView.as_view()),
    path("app/version", AppVersionView.as_view()),
]

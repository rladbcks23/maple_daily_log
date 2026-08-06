from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AppVersionView,
    CheckNewNoticesView,
    CurrentNoticesView,
    FeedbackCreateView,
    LatestSundayEventView,
    NexonBasicView,
    NexonCharactersView,
    NexonOcidView,
    NexonSchedulerView,
    NoticeSnapshotViewSet,
    SundayEventSnapshotViewSet,
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
    path("app/version", AppVersionView.as_view()),
    path("feedback", FeedbackCreateView.as_view()),
]

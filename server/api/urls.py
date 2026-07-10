from django.urls import path

from . import views


urlpatterns = [
    path("meta/nexon-endpoints", views.nexon_endpoints),
    path("meta/snapshot-bundles", views.snapshot_bundles),
    path("sync/characters", views.sync_characters),
    path("sync/snapshot", views.sync_snapshot),
    path("characters", views.characters),
    path("characters/<uuid:character_id>", views.character_detail),
    path("snapshots", views.create_snapshot),
    path("snapshots/latest", views.latest_snapshot),
    path("play-sessions/start", views.start_session),
    path("play-sessions/<uuid:session_id>/end", views.end_session),
    path("reports/<str:report_type>", views.generate_report),
    path("reports", views.reports),
    path("scheduler/missing-tasks", views.missing_tasks),
]

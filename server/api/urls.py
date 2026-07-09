from django.urls import path

from api import views


urlpatterns = [
    path("health", views.health, name="health"),
    path("api/sync/characters", views.sync_characters, name="sync-characters"),
    path("api/sync/snapshot", views.sync_snapshot, name="sync-snapshot"),
    path("api/reports/daily", views.create_daily_report, name="create-daily-report"),
]

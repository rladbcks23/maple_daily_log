from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from django.views.static import serve

from api.views import health

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health", health),
    path("api/", include("api.urls")),
    # Small personal project, no CDN/object storage — Django serves feedback
    # attachments directly. Fine at this scale, revisit if traffic grows.
    path(
        "media/<path:path>",
        serve,
        {"document_root": settings.MEDIA_ROOT},
    ),
]

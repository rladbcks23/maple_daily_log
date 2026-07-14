from django.contrib import admin
from django.urls import include, path

from api.views import health

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health", health),
    path("api/", include("api.urls")),
]

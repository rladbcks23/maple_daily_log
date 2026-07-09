import os
from pathlib import Path

from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "local-dev-only-change-me")
DEBUG = os.environ.get("DJANGO_DEBUG", "false").lower() == "true"
ALLOWED_HOSTS = [host.strip() for host in os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",") if host.strip()]

INSTALLED_APPS = [
    "django.contrib.staticfiles",
    "rest_framework",
    "api",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "maple_daily_log.urls"
WSGI_APPLICATION = "maple_daily_log.wsgi.application"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
STATIC_URL = "static/"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "APP_DIRS": True,
        "DIRS": [],
        "OPTIONS": {},
    },
]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "api.auth.AdminTokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "UNAUTHENTICATED_USER": None,
    "UNAUTHENTICATED_TOKEN": None,
}

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": os.environ.get("SQLITE_PATH", BASE_DIR / "db.sqlite3"),
    },
}

MAPLE = {
    "ADMIN_TOKEN": os.environ.get("ADMIN_TOKEN", ""),
    "NEXON_API_KEY": os.environ.get("NEXON_API_KEY", ""),
    "NEXON_API_BASE_URL": os.environ.get("NEXON_API_BASE_URL", "https://open.api.nexon.com"),
    "TIMEZONE": os.environ.get("MAPLE_TIMEZONE", "Asia/Seoul"),
    "NEXON_REQUESTS_PER_SECOND": int(os.environ.get("NEXON_REQUESTS_PER_SECOND", "5")),
    "NEXON_REQUESTS_PER_DAY": int(os.environ.get("NEXON_REQUESTS_PER_DAY", "1000")),
}

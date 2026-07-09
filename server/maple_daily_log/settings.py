import os
from pathlib import Path
from urllib.parse import parse_qs, urlparse


BASE_DIR = Path(__file__).resolve().parent.parent

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

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "api.auth.AdminTokenAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}


def database_config():
    database_url = os.environ.get("DATABASE_URL", "")
    if database_url.startswith("jdbc:"):
        database_url = database_url.removeprefix("jdbc:")

    parsed = urlparse(database_url)
    query = parse_qs(parsed.query)

    return {
        "ENGINE": "django.db.backends.postgresql",
        "HOST": parsed.hostname or os.environ.get("DATABASE_HOST", ""),
        "PORT": parsed.port or int(os.environ.get("DATABASE_PORT", "5432")),
        "NAME": parsed.path.lstrip("/") or os.environ.get("DATABASE_NAME", "postgres"),
        "USER": os.environ.get("DATABASE_USERNAME") or parsed.username or "postgres",
        "PASSWORD": os.environ.get("DATABASE_PASSWORD") or parsed.password or "",
        "OPTIONS": {
            "sslmode": query.get("sslmode", [os.environ.get("DATABASE_SSLMODE", "require")])[0],
        },
    }


DATABASES = {
    "default": database_config(),
}

MAPLE = {
    "ADMIN_TOKEN": os.environ.get("ADMIN_TOKEN", ""),
    "NEXON_API_KEY": os.environ.get("NEXON_API_KEY", ""),
    "NEXON_API_BASE_URL": os.environ.get("NEXON_API_BASE_URL", "https://open.api.nexon.com"),
    "TIMEZONE": os.environ.get("MAPLE_TIMEZONE", "Asia/Seoul"),
    "NEXON_REQUESTS_PER_SECOND": int(os.environ.get("NEXON_REQUESTS_PER_SECOND", "5")),
    "NEXON_REQUESTS_PER_DAY": int(os.environ.get("NEXON_REQUESTS_PER_DAY", "1000")),
}

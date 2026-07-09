import os

from django.core.wsgi import get_wsgi_application


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "maple_daily_log.settings")

application = get_wsgi_application()

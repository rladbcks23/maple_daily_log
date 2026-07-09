from django.conf import settings
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed


class AdminUser:
    is_authenticated = True


class AdminTokenAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        expected = settings.MAPLE["ADMIN_TOKEN"]
        header = request.headers.get("Authorization", "")

        if not expected:
            raise AuthenticationFailed("ADMIN_TOKEN is not configured.")

        prefix = f"{self.keyword} "
        if not header.startswith(prefix):
            raise AuthenticationFailed("Missing bearer token.")

        token = header.removeprefix(prefix)
        if token != expected:
            raise AuthenticationFailed("Invalid admin token.")

        return AdminUser(), None

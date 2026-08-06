import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = (
        "Create (or update the password of) a superuser from the "
        "DJANGO_SUPERUSER_USERNAME / DJANGO_SUPERUSER_EMAIL / "
        "DJANGO_SUPERUSER_PASSWORD environment variables. Safe to run on "
        "every deploy: does nothing if the required env vars are missing."
    )

    def handle(self, *args, **options):
        username = os.getenv("DJANGO_SUPERUSER_USERNAME")
        password = os.getenv("DJANGO_SUPERUSER_PASSWORD")
        email = os.getenv("DJANGO_SUPERUSER_EMAIL", "")

        if not username or not password:
            self.stdout.write(
                "DJANGO_SUPERUSER_USERNAME/DJANGO_SUPERUSER_PASSWORD not set, "
                "skipping."
            )
            return

        User = get_user_model()
        user, created = User.objects.get_or_create(
            username=username,
            defaults={"email": email, "is_staff": True, "is_superuser": True},
        )
        user.email = email
        user.is_staff = True
        user.is_superuser = True
        user.set_password(password)
        user.save()

        self.stdout.write(
            self.style.SUCCESS(
                f"Superuser '{username}' {'created' if created else 'updated'}."
            )
        )

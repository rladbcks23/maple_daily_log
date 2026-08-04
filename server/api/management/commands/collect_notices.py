from django.core.management.base import BaseCommand

from api.services import collect_and_store_notice_items


class Command(BaseCommand):
    help = "Collect Nexon notices and store shared notice snapshots."

    def handle(self, *args, **options):
        result = collect_and_store_notice_items()
        self.stdout.write(
            self.style.SUCCESS(
                "Collected notices: "
                f"{len(result['items'])} active, "
                f"{len(result['newItems'])} new, "
                f"{len(result['endedEvents'])} ended."
            )
        )

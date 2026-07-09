from rest_framework import serializers


class SnapshotRequestSerializer(serializers.Serializer):
    ocid = serializers.CharField()
    snapshotType = serializers.ChoiceField(
        required=False,
        allow_blank=True,
        choices=["app_start", "game_start", "game_end", "force_refresh", "manual", "scheduled"],
    )
    playDate = serializers.DateField(required=False)

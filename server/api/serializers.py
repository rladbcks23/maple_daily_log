from rest_framework import serializers


class SnapshotRequestSerializer(serializers.Serializer):
    ocid = serializers.CharField(required=False, allow_blank=True)
    characterId = serializers.CharField(required=False, allow_blank=True)
    characterName = serializers.CharField(required=False, allow_blank=True)
    snapshotType = serializers.ChoiceField(
        required=False,
        allow_blank=True,
        choices=["app_start", "game_start", "game_end", "force_refresh", "manual", "scheduled"],
    )
    playDate = serializers.DateField(required=False)

    def validate(self, attrs):
        if not any(attrs.get(field) for field in ("ocid", "characterId", "characterName")):
            raise serializers.ValidationError("ocid, characterId, or characterName is required.")
        return attrs

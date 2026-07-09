package com.mapledailylog.nexon;

public record NexonCharacterSummary(
        String ocid,
        String characterName,
        String worldName,
        String characterClass,
        Integer characterLevel
) {
}

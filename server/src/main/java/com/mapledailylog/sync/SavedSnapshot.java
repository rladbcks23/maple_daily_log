package com.mapledailylog.sync;

import java.time.LocalDate;
import java.util.UUID;

public record SavedSnapshot(
        UUID characterId,
        UUID snapshotId,
        String characterName,
        Integer characterLevel,
        LocalDate playDate
) {
}

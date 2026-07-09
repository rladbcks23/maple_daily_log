package com.mapledailylog.sync;

import jakarta.validation.constraints.NotBlank;
import java.time.LocalDate;

public record SnapshotRequest(
        @NotBlank String ocid,
        String snapshotType,
        LocalDate playDate
) {
}

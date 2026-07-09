package com.mapledailylog.sync;

import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class SyncService {

    public Map<String, Object> syncCharacters() {
        return Map.of(
                "status", "planned",
                "message", "Nexon API character synchronization will be implemented here."
        );
    }

    public Map<String, Object> createSnapshot(SnapshotRequest request) {
        return Map.of(
                "status", "planned",
                "ocid", request.ocid(),
                "snapshotType", request.snapshotType(),
                "message", "Nexon API data will be collected and saved into character_snapshots."
        );
    }
}

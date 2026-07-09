package com.mapledailylog.sync;

import com.mapledailylog.config.MapleProperties;
import com.mapledailylog.nexon.NexonApiClient;
import com.mapledailylog.nexon.NexonSnapshotBundle;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SyncService {

    private static final String DEFAULT_SNAPSHOT_TYPE = "force_refresh";
    private static final Set<String> ALLOWED_SNAPSHOT_TYPES = Set.of(
            "app_start",
            "game_start",
            "game_end",
            "force_refresh",
            "manual",
            "scheduled"
    );

    private final NexonApiClient nexonApiClient;
    private final SnapshotRepository snapshotRepository;
    private final ZoneId zoneId;

    public SyncService(
            NexonApiClient nexonApiClient,
            SnapshotRepository snapshotRepository,
            MapleProperties properties
    ) {
        this.nexonApiClient = nexonApiClient;
        this.snapshotRepository = snapshotRepository;
        this.zoneId = ZoneId.of(properties.timezone());
    }

    public Map<String, Object> syncCharacters() {
        return Map.of(
                "status", "planned",
                "message", "Nexon API character synchronization will be implemented here."
        );
    }

    @Transactional
    public Map<String, Object> createSnapshot(SnapshotRequest request) {
        String snapshotType = snapshotType(request);
        LocalDate playDate = playDate(request);
        NexonSnapshotBundle bundle = nexonApiClient.fetchSnapshotBundle(request.ocid());
        SavedSnapshot savedSnapshot = snapshotRepository.saveSnapshot(bundle, snapshotType, playDate);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status", "saved");
        response.put("ocid", request.ocid());
        response.put("characterId", savedSnapshot.characterId());
        response.put("snapshotId", savedSnapshot.snapshotId());
        response.put("characterName", savedSnapshot.characterName());
        response.put("characterLevel", savedSnapshot.characterLevel());
        response.put("snapshotType", snapshotType);
        response.put("playDate", playDate);
        response.put("apiCallsUsed", bundle.apiCallsUsed());
        response.put("sections", List.copyOf(bundle.sections().keySet()));
        response.put("message", "Nexon API data was fetched and saved into character_snapshots.");
        return response;
    }

    private String snapshotType(SnapshotRequest request) {
        if (request.snapshotType() == null || request.snapshotType().isBlank()) {
            return DEFAULT_SNAPSHOT_TYPE;
        }
        String snapshotType = request.snapshotType();
        if (!ALLOWED_SNAPSHOT_TYPES.contains(snapshotType)) {
            throw new IllegalArgumentException("Unsupported snapshot type: " + snapshotType);
        }
        return snapshotType;
    }

    private LocalDate playDate(SnapshotRequest request) {
        if (request.playDate() != null) {
            return request.playDate();
        }
        return LocalDate.now(zoneId);
    }
}

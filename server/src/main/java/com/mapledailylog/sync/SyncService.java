package com.mapledailylog.sync;

import com.mapledailylog.nexon.NexonApiClient;
import com.mapledailylog.nexon.NexonSnapshotBundle;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class SyncService {

    private final NexonApiClient nexonApiClient;

    public SyncService(NexonApiClient nexonApiClient) {
        this.nexonApiClient = nexonApiClient;
    }

    public Map<String, Object> syncCharacters() {
        return Map.of(
                "status", "planned",
                "message", "Nexon API character synchronization will be implemented here."
        );
    }

    public Map<String, Object> createSnapshot(SnapshotRequest request) {
        NexonSnapshotBundle bundle = nexonApiClient.fetchSnapshotBundle(request.ocid());

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status", "fetched");
        response.put("ocid", request.ocid());
        response.put("snapshotType", request.snapshotType());
        response.put("playDate", request.playDate());
        response.put("apiCallsUsed", bundle.apiCallsUsed());
        response.put("sections", List.copyOf(bundle.sections().keySet()));
        response.put("message", "Nexon API data was fetched. Database saving will be implemented next.");
        return response;
    }
}

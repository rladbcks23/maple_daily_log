package com.mapledailylog.sync;

import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/sync")
public class SyncController {

    private final SyncService syncService;

    public SyncController(SyncService syncService) {
        this.syncService = syncService;
    }

    @PostMapping("/characters")
    public Map<String, Object> syncCharacters() {
        return syncService.syncCharacters();
    }

    @PostMapping("/snapshot")
    public Map<String, Object> createSnapshot(@Valid @RequestBody SnapshotRequest request) {
        return syncService.createSnapshot(request);
    }
}

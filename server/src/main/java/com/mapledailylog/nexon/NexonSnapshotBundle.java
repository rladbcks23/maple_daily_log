package com.mapledailylog.nexon;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public record NexonSnapshotBundle(
        String ocid,
        Instant collectedAt,
        int apiCallsUsed,
        Map<String, JsonNode> sections
) {
    public static Builder builder(String ocid) {
        return new Builder(ocid);
    }

    public static class Builder {
        private final String ocid;
        private final Instant collectedAt = Instant.now();
        private final Map<String, JsonNode> sections = new LinkedHashMap<>();
        private int apiCallsUsed;

        private Builder(String ocid) {
            this.ocid = ocid;
        }

        public Builder add(String name, JsonNode body) {
            sections.put(name, body);
            apiCallsUsed++;
            return this;
        }

        public NexonSnapshotBundle build() {
            return new NexonSnapshotBundle(ocid, collectedAt, apiCallsUsed, Collections.unmodifiableMap(new LinkedHashMap<>(sections)));
        }
    }
}

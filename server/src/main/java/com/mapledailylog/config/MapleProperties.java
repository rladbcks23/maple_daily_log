package com.mapledailylog.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "maple")
public record MapleProperties(
        String adminToken,
        String nexonApiKey,
        String timezone,
        NexonRateLimit nexonRateLimit
) {
    public record NexonRateLimit(
            int requestsPerSecond,
            int requestsPerDay
    ) {
    }
}

package com.mapledailylog.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "maple")
public record MapleProperties(
        String adminToken,
        String nexonApiKey,
        String timezone
) {
}

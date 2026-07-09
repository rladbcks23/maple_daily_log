package com.mapledailylog.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(MapleProperties.class)
public class AppConfig {

    @Bean
    public RestClient nexonRestClient(MapleProperties properties) {
        return RestClient.builder()
                .baseUrl(properties.nexonApiBaseUrl())
                .defaultHeader("x-nxopen-api-key", properties.nexonApiKey())
                .build();
    }
}

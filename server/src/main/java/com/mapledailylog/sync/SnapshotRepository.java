package com.mapledailylog.sync;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.mapledailylog.nexon.NexonSnapshotBundle;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class SnapshotRepository {

    private final JdbcTemplate jdbcTemplate;
    private final ObjectMapper objectMapper;

    public SnapshotRepository(JdbcTemplate jdbcTemplate, ObjectMapper objectMapper) {
        this.jdbcTemplate = jdbcTemplate;
        this.objectMapper = objectMapper;
    }

    public SavedSnapshot saveSnapshot(NexonSnapshotBundle bundle, String snapshotType, LocalDate playDate) {
        JsonNode basic = bundle.sections().get("basic");
        UUID characterId = upsertCharacter(bundle.ocid(), basic);
        JsonNode snapshotJson = buildSnapshotJson(bundle);

        Integer level = integerValue(basic, "character_level");
        BigDecimal expRate = decimalValue(basic, "character_exp_rate");
        BigDecimal combatPower = combatPower(bundle.sections().get("stat"));

        UUID snapshotId = insertSnapshot(
                characterId,
                snapshotType,
                playDate,
                level,
                expRate,
                combatPower,
                snapshotJson,
                bundle.collectedAt()
        );

        return new SavedSnapshot(
                characterId,
                snapshotId,
                textValue(basic, "character_name", bundle.ocid()),
                level,
                playDate
        );
    }

    private UUID upsertCharacter(String ocid, JsonNode basic) {
        return jdbcTemplate.queryForObject("""
                insert into characters (
                    ocid,
                    character_name,
                    world_name,
                    character_class,
                    character_class_level,
                    character_level,
                    last_synced_at,
                    updated_at
                )
                values (?, ?, ?, ?, ?, ?, now(), now())
                on conflict (ocid) do update set
                    character_name = excluded.character_name,
                    world_name = excluded.world_name,
                    character_class = excluded.character_class,
                    character_class_level = excluded.character_class_level,
                    character_level = excluded.character_level,
                    last_synced_at = now(),
                    updated_at = now()
                returning id
                """,
                UUID.class,
                ocid,
                textValue(basic, "character_name", ocid),
                textValue(basic, "world_name", null),
                textValue(basic, "character_class", null),
                textValue(basic, "character_class_level", null),
                integerValue(basic, "character_level")
        );
    }

    private UUID insertSnapshot(
            UUID characterId,
            String snapshotType,
            LocalDate playDate,
            Integer characterLevel,
            BigDecimal expRate,
            BigDecimal combatPower,
            JsonNode snapshotJson,
            Instant recordedAt
    ) {
        return jdbcTemplate.queryForObject("""
                insert into character_snapshots (
                    character_id,
                    snapshot_type,
                    play_date,
                    recorded_at,
                    character_level,
                    exp_rate,
                    combat_power,
                    snapshot_json
                )
                values (?, ?, ?, ?, ?, ?, ?, cast(? as jsonb))
                returning id
                """,
                UUID.class,
                characterId,
                snapshotType,
                playDate,
                recordedAt,
                characterLevel,
                expRate,
                combatPower,
                writeJson(snapshotJson)
        );
    }

    private ObjectNode buildSnapshotJson(NexonSnapshotBundle bundle) {
        ObjectNode root = objectMapper.createObjectNode();
        root.put("ocid", bundle.ocid());
        root.put("collectedAt", bundle.collectedAt().toString());
        root.put("apiCallsUsed", bundle.apiCallsUsed());

        ObjectNode sections = objectMapper.createObjectNode();
        bundle.sections().forEach(sections::set);
        root.set("sections", sections);

        return root;
    }

    private String writeJson(JsonNode jsonNode) {
        try {
            return objectMapper.writeValueAsString(jsonNode);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Failed to serialize snapshot JSON.", exception);
        }
    }

    private String textValue(JsonNode node, String field, String fallback) {
        if (node == null || node.get(field) == null || node.get(field).isNull()) {
            return fallback;
        }
        String value = node.get(field).asText();
        return value == null || value.isBlank() ? fallback : value;
    }

    private Integer integerValue(JsonNode node, String field) {
        if (node == null || node.get(field) == null || node.get(field).isNull()) {
            return null;
        }
        return node.get(field).asInt();
    }

    private BigDecimal decimalValue(JsonNode node, String field) {
        if (node == null || node.get(field) == null || node.get(field).isNull()) {
            return null;
        }
        String value = node.get(field).asText();
        if (value == null || value.isBlank()) {
            return null;
        }
        return new BigDecimal(value.replace(",", ""));
    }

    private BigDecimal combatPower(JsonNode stat) {
        JsonNode finalStats = stat == null ? null : stat.get("final_stat");
        if (finalStats == null || !finalStats.isArray()) {
            return null;
        }

        for (JsonNode finalStat : finalStats) {
            if ("전투력".equals(textValue(finalStat, "stat_name", null))) {
                return decimalValue(finalStat, "stat_value");
            }
        }

        return null;
    }
}

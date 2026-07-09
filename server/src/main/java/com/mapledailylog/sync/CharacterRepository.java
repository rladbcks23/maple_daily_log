package com.mapledailylog.sync;

import com.mapledailylog.nexon.NexonCharacterSummary;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class CharacterRepository {

    private final JdbcTemplate jdbcTemplate;

    public CharacterRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public int upsertCharacters(List<NexonCharacterSummary> characters) {
        int saved = 0;
        for (NexonCharacterSummary character : characters) {
            if (character.ocid() == null || character.ocid().isBlank()) {
                continue;
            }
            upsertCharacter(character);
            saved++;
        }
        return saved;
    }

    private void upsertCharacter(NexonCharacterSummary character) {
        jdbcTemplate.update("""
                insert into characters (
                    ocid,
                    character_name,
                    world_name,
                    character_class,
                    character_level,
                    last_synced_at,
                    updated_at
                )
                values (?, ?, ?, ?, ?, now(), now())
                on conflict (ocid) do update set
                    character_name = excluded.character_name,
                    world_name = excluded.world_name,
                    character_class = excluded.character_class,
                    character_level = excluded.character_level,
                    last_synced_at = now(),
                    updated_at = now()
                """,
                character.ocid(),
                fallbackName(character),
                character.worldName(),
                character.characterClass(),
                character.characterLevel()
        );
    }

    private String fallbackName(NexonCharacterSummary character) {
        if (character.characterName() == null || character.characterName().isBlank()) {
            return character.ocid();
        }
        return character.characterName();
    }
}

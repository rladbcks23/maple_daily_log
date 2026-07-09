package com.mapledailylog.nexon;

import com.fasterxml.jackson.databind.JsonNode;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriBuilder;

@Component
public class NexonApiClient {

    private final RestClient restClient;

    public NexonApiClient(RestClient nexonRestClient) {
        this.restClient = nexonRestClient;
    }

    public String findOcidByCharacterName(String characterName) {
        JsonNode body = get(uriBuilder -> uriBuilder
                .path("/maplestory/v1/id")
                .queryParam("character_name", characterName)
                .build());

        JsonNode ocid = body.get("ocid");
        if (ocid == null || ocid.asText().isBlank()) {
            throw new NexonApiException("Nexon API response did not include ocid.");
        }

        return ocid.asText();
    }

    public List<NexonCharacterSummary> fetchCharacterList() {
        JsonNode body = get(uriBuilder -> uriBuilder
                .path("/maplestory/v1/character/list")
                .build());

        List<NexonCharacterSummary> characters = new ArrayList<>();
        collectCharacters(body, characters);
        return List.copyOf(characters);
    }

    public NexonSnapshotBundle fetchSnapshotBundle(String ocid) {
        NexonSnapshotBundle.Builder bundle = NexonSnapshotBundle.builder(ocid);

        snapshotEndpoints().forEach((section, path) ->
                bundle.add(section, getWithOcid(path, ocid))
        );

        return bundle.build();
    }

    public JsonNode fetchCharacterBasic(String ocid) {
        return getWithOcid("/maplestory/v1/character/basic", ocid);
    }

    public JsonNode fetchStarforceHistory(String count, String date) {
        return get(uriBuilder -> uriBuilder
                .path("/maplestory/v1/history/starforce")
                .queryParam("count", count)
                .queryParam("date", date)
                .build());
    }

    public JsonNode fetchCubeHistory(String count, String date) {
        return get(uriBuilder -> uriBuilder
                .path("/maplestory/v1/history/cube")
                .queryParam("count", count)
                .queryParam("date", date)
                .build());
    }

    public JsonNode fetchPotentialHistory(String count, String date) {
        return get(uriBuilder -> uriBuilder
                .path("/maplestory/v1/history/potential")
                .queryParam("count", count)
                .queryParam("date", date)
                .build());
    }

    private JsonNode getWithOcid(String path, String ocid) {
        return get(uriBuilder -> uriBuilder
                .path(path)
                .queryParam("ocid", ocid)
                .build());
    }

    private JsonNode get(UriFactory uriFactory) {
        try {
            JsonNode body = restClient.get()
                    .uri(uriFactory::build)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (request, response) -> {
                        throw new NexonApiException("Nexon API request failed with status " + response.getStatusCode());
                    })
                    .body(JsonNode.class);
            if (body == null) {
                throw new NexonApiException("Nexon API response body was empty.");
            }
            return body;
        } catch (NexonApiException exception) {
            throw exception;
        } catch (RuntimeException exception) {
            throw new NexonApiException("Nexon API request failed.", exception);
        }
    }

    private Map<String, String> snapshotEndpoints() {
        return Map.ofEntries(
                Map.entry("basic", "/maplestory/v1/character/basic"),
                Map.entry("stat", "/maplestory/v1/character/stat"),
                Map.entry("hyperStat", "/maplestory/v1/character/hyper-stat"),
                Map.entry("ability", "/maplestory/v1/character/ability"),
                Map.entry("itemEquipment", "/maplestory/v1/character/item-equipment"),
                Map.entry("symbolEquipment", "/maplestory/v1/character/symbol-equipment"),
                Map.entry("vmatrix", "/maplestory/v1/character/vmatrix"),
                Map.entry("hexamatrix", "/maplestory/v1/character/hexamatrix"),
                Map.entry("hexamatrixStat", "/maplestory/v1/character/hexamatrix-stat")
        );
    }

    private void collectCharacters(JsonNode node, List<NexonCharacterSummary> characters) {
        if (node == null || node.isNull()) {
            return;
        }

        if (node.isObject() && node.hasNonNull("ocid")) {
            characters.add(toCharacterSummary(node));
            return;
        }

        if (node.isArray()) {
            node.forEach(child -> collectCharacters(child, characters));
            return;
        }

        JsonNode characterList = node.get("character_list");
        if (characterList != null) {
            collectCharacters(characterList, characters);
        }

        JsonNode accountList = node.get("account_list");
        if (accountList != null) {
            collectCharacters(accountList, characters);
        }
    }

    private NexonCharacterSummary toCharacterSummary(JsonNode node) {
        return new NexonCharacterSummary(
                textValue(node, "ocid"),
                textValue(node, "character_name"),
                textValue(node, "world_name"),
                textValue(node, "character_class"),
                integerValue(node, "character_level")
        );
    }

    private String textValue(JsonNode node, String field) {
        JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return null;
        }
        return value.asText();
    }

    private Integer integerValue(JsonNode node, String field) {
        JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return null;
        }
        return value.asInt();
    }

    @FunctionalInterface
    private interface UriFactory {
        URI build(UriBuilder uriBuilder);
    }
}

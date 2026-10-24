package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Base64;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * Stats surface behaviour that does not need real attestation crypto:
 * rejection paths, the dev simulator bypass, validation, idempotency,
 * and the admin-token summary (incl. the PT day bucket).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-stats;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class StatsEndpointTest {

    @Autowired
    private MockMvc mvc;

    private final ObjectMapper json = new ObjectMapper();

    private static String oneEventBody(UUID installId, String eventId, String type) {
        return "{\"installId\":\"" + installId + "\",\"sessionId\":\"" + UUID.randomUUID() + "\",\"events\":[{"
                + "\"eventId\":\"" + eventId + "\",\"type\":\"" + type + "\",\"clientTs\":1790000000123,"
                + (type.equals("analysis_completed")
                        ? "\"verdict\":\"RIPE\""
                        : "\"slot\":\"rewarded_main\",\"unitSource\":\"server\"")
                + "}]}";
    }

    @Test
    void uploadWithoutAssertionIsUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/stats/events")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(oneEventBody(UUID.randomUUID(), UUID.randomUUID().toString(), "ad_requested")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void uploadWithGarbageAssertionIsUnauthorized() throws Exception {
        String garbage = Base64.getEncoder().encodeToString(new byte[] {9, 9, 9, 9});
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Key-Id", "no-such-key")
                        .header("X-Assertion", garbage)
                        .header("X-Challenge", garbage)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(oneEventBody(UUID.randomUUID(), UUID.randomUUID().toString(), "ad_requested")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void bypassUploadIsIdempotentAndValidates() throws Exception {
        UUID installId = UUID.randomUUID();
        String eventId = UUID.randomUUID().toString();
        String body = oneEventBody(installId, eventId, "ad_requested");

        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.accepted").value(1));
        // Identical re-upload: accepted, but nothing new is stored.
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.accepted").value(0));

        String badType = oneEventBody(installId, UUID.randomUUID().toString(), "not_a_real_type");
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content(badType))
                .andExpect(status().isBadRequest());
    }

    @Test
    void oversizedBatchIsRejected() throws Exception {
        StringBuilder body = new StringBuilder("{\"installId\":\"" + UUID.randomUUID() + "\",\"events\":[");
        for (int i = 0; i < StatsController.MAX_BATCH + 1; i++) {
            if (i > 0) {
                body.append(',');
            }
            body.append("{\"eventId\":\"").append(UUID.randomUUID())
                    .append("\",\"type\":\"ad_shown\",\"clientTs\":1790000000123,\"slot\":\"rewarded_main\"}");
        }
        body.append("]}");
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content(body.toString()))
                .andExpect(status().isBadRequest());
    }

    @Test
    void summaryRequiresTokenAndAggregatesToday() throws Exception {
        mvc.perform(get("/api/v1/stats/summary").param("days", "7"))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/v1/stats/summary").param("days", "7")
                        .header("X-Admin-Token", "wrong"))
                .andExpect(status().isForbidden());

        JsonNode before = summary(7);
        long analysesBefore = todayRow(before).get("analyses").asLong();
        long requestedBefore = todayRow(before).get("adRequested").asLong();

        UUID installId = UUID.randomUUID();
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(oneEventBody(installId, UUID.randomUUID().toString(), "analysis_completed")))
                .andExpect(status().isAccepted());
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(oneEventBody(installId, UUID.randomUUID().toString(), "ad_requested")))
                .andExpect(status().isAccepted());

        JsonNode after = summary(7);
        JsonNode today = todayRow(after);
        assertEquals(analysesBefore + 1, today.get("analyses").asLong());
        assertEquals(requestedBefore + 1, today.get("adRequested").asLong());
        assertEquals(1, today.get("verdicts").get("RIPE").asLong());
        assertTrue(today.get("activeInstalls").asLong() >= 1);
    }

    private JsonNode summary(int days) throws Exception {
        MvcResult result = mvc.perform(get("/api/v1/stats/summary")
                        .param("days", String.valueOf(days))
                        .header("X-Admin-Token", "test-admin-token"))
                .andExpect(status().isOk())
                .andReturn();
        return json.readTree(result.getResponse().getContentAsString());
    }

    private static JsonNode todayRow(JsonNode summary) {
        String today = LocalDate.now(ZoneId.of("America/Los_Angeles")).toString();
        for (JsonNode day : summary.get("days")) {
            if (today.equals(day.get("date").asText())) {
                return day;
            }
        }
        throw new AssertionError("summary has no row for today (" + today + ")");
    }
}

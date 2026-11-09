package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.AdFreeLedgerEntry;
import dev.melonthump.contrib.AdFreeLedgerRepository;
import dev.melonthump.contrib.LedgerReason;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/**
 * Contributor-facing 2.0 endpoints: application submit, idempotent
 * re-post, the APPLICATION_SUBMITTED audit row, input validation, and
 * the status + ad-free balance query.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-contrib-api;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class ContributionApiTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private AdFreeLedgerRepository ledger;

    @Autowired
    private org.springframework.transaction.support.TransactionTemplate txTemplate;

    private final ObjectMapper json = new ObjectMapper();

    private ResultActions apply(String body) throws Exception {
        return mvc.perform(post("/api/v1/contributions/applications")
                        .header("X-Attest-Bypass", "simulator")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private String body(UUID id, String note) throws Exception {
        return json.writeValueAsString(Map.of("contributorId", id.toString(), "note", note));
    }

    private int auditRows(UUID id) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM audit_log WHERE object_id = ?", Integer.class, id.toString());
    }

    @Test
    void submitCreatesPendingApplicationAndAuditRow() throws Exception {
        UUID id = UUID.randomUUID();
        apply(body(id, "Alex, melon farmer in Fresno"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.contributorId").value(id.toString()))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.createdAt").isString())
                .andExpect(jsonPath("$.updatedAt").isString());

        assertEquals("Alex, melon farmer in Fresno",
                jdbc.queryForObject("SELECT note FROM contributors WHERE contributor_id = ?", String.class, id));
        Map<String, Object> row = jdbc.queryForMap(
                "SELECT actor, action, object_type, before_json, after_json FROM audit_log WHERE object_id = ?",
                id.toString());
        assertEquals(id.toString(), row.get("actor"));
        assertEquals("APPLICATION_SUBMITTED", row.get("action"));
        assertEquals("CONTRIBUTOR", row.get("object_type"));
        assertEquals(null, row.get("before_json"));
        JsonNode after = json.readTree((String) row.get("after_json"));
        assertEquals("PENDING", after.get("status").asText());
        assertEquals(id.toString(), after.get("contributorId").asText());
    }

    @Test
    void repostIsIdempotentAndKeepsOriginalNote() throws Exception {
        UUID id = UUID.randomUUID();
        String first = apply(body(id, "first note")).andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String second = apply(body(id, "a different note")).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertEquals(json.readTree(first), json.readTree(second), "re-post returns the stored record unchanged");
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM contributors WHERE contributor_id = ?", Integer.class, id));
        assertEquals("first note",
                jdbc.queryForObject("SELECT note FROM contributors WHERE contributor_id = ?", String.class, id));
        assertEquals(1, auditRows(id), "no audit row for an idempotent re-post");
    }

    @Test
    void noteIsTrimmed() throws Exception {
        UUID id = UUID.randomUUID();
        apply(body(id, "  Sam  ")).andExpect(status().isCreated());
        assertEquals("Sam",
                jdbc.queryForObject("SELECT note FROM contributors WHERE contributor_id = ?", String.class, id));
    }

    @Test
    void invalidApplicationsAreRejected() throws Exception {
        UUID id = UUID.randomUUID();
        apply("{\"contributorId\":\"" + id + "\"}").andExpect(status().isBadRequest());
        apply(body(id, "")).andExpect(status().isBadRequest());
        apply(body(id, "   ")).andExpect(status().isBadRequest());
        apply("{\"note\":\"hello\"}").andExpect(status().isBadRequest());
        apply("{\"contributorId\":\"not-a-uuid\",\"note\":\"hello\"}").andExpect(status().isBadRequest());
        apply("not json").andExpect(status().isBadRequest());
        apply(body(id, "x".repeat(1001))).andExpect(status().isBadRequest());

        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM contributors WHERE contributor_id = ?", Integer.class, id));
        assertEquals(0, auditRows(id));

        apply(body(id, "x".repeat(1000))).andExpect(status().isCreated());
    }

    @Test
    void statusReturnsStandingAndZeroBalance() throws Exception {
        UUID id = UUID.randomUUID();
        apply(body(id, "note")).andExpect(status().isCreated());
        mvc.perform(get("/api/v1/contributions/status")
                        .header("X-Attest-Bypass", "simulator").param("contributorId", id.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.contributorId").value(id.toString()))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.adFreeBalance").value(0));
    }

    @Test
    void statusReportsLedgerBalanceSum() throws Exception {
        UUID id = UUID.randomUUID();
        apply(body(id, "note")).andExpect(status().isCreated());
        txTemplate.executeWithoutResult(s -> {
            ledger.save(new AdFreeLedgerEntry(id, 5, LedgerReason.SAMPLE_APPROVED, "1"));
            ledger.save(new AdFreeLedgerEntry(id, 5, LedgerReason.SAMPLE_APPROVED, "2"));
            ledger.save(new AdFreeLedgerEntry(id, -3, LedgerReason.VOID_CLAWBACK, "2"));
        });
        mvc.perform(get("/api/v1/contributions/status")
                        .header("X-Attest-Bypass", "simulator").param("contributorId", id.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adFreeBalance").value(7));
    }

    @Test
    void statusOfUnknownContributorIs404() throws Exception {
        mvc.perform(get("/api/v1/contributions/status")
                        .header("X-Attest-Bypass", "simulator").param("contributorId", UUID.randomUUID().toString()))
                .andExpect(status().isNotFound());
    }

    @Test
    void statusWithMalformedOrMissingIdIs400() throws Exception {
        mvc.perform(get("/api/v1/contributions/status")
                        .header("X-Attest-Bypass", "simulator").param("contributorId", "nope"))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/contributions/status")
                        .header("X-Attest-Bypass", "simulator")).andExpect(status().isBadRequest());
    }
}

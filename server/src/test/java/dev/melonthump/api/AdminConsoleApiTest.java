package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import dev.melonthump.contrib.ContributionService;
import java.util.ArrayList;
import java.util.List;
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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * S4: the Cloudflare Access identity as audit actor on every admin write
 * (header present → the email; absent / blank → {@code owner}), and
 * Pepper's preliminary review (write, validation, visibility in the admin
 * shapes, contributor-facing shapes unchanged, actor {@code pepper}).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-s4-console;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdminConsoleApiTest {

    static final String EMAIL_HEADER = "Cf-Access-Authenticated-User-Email";
    static final String EMAIL = "owner@example.test";
    static final String BYPASS = "X-Attest-Bypass";

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ContributionService contributions;

    private S4Fixtures fx() {
        return new S4Fixtures(mvc, contributions);
    }

    private static MockHttpServletRequestBuilder as(MockHttpServletRequestBuilder b) {
        return b.header(EMAIL_HEADER, EMAIL);
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder b, String body) {
        return b.contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private String lastActor(String objectType, String objectId) {
        return jdbc.queryForObject("SELECT actor FROM audit_log WHERE object_type = ? AND object_id = ? "
                + "ORDER BY id DESC LIMIT 1", String.class, objectType, objectId);
    }

    private String lastAction(String objectType, String objectId) {
        return jdbc.queryForObject("SELECT action FROM audit_log WHERE object_type = ? AND object_id = ? "
                + "ORDER BY id DESC LIMIT 1", String.class, objectType, objectId);
    }

    private int auditCount() {
        return jdbc.queryForObject("SELECT COUNT(*) FROM audit_log", Integer.class);
    }

    // ---- actor resolution -----------------------------------------------------------

    @Test
    void accessEmailIsTheActorOnEveryAdminWrite() throws Exception {
        S4Fixtures fx = fx();

        // Contributors: approve / revoke / decline.
        UUID c = fx.pendingContributor();
        mvc.perform(as(post("/api/admin/applications/" + c + "/approve"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("CONTRIBUTOR", c.toString()));
        mvc.perform(as(post("/api/admin/contributors/" + c + "/revoke"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("CONTRIBUTOR", c.toString()));
        UUID d = fx.pendingContributor();
        mvc.perform(as(post("/api/admin/applications/" + d + "/decline"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("CONTRIBUTOR", d.toString()));

        // Samples: approve / return / void.
        UUID a = fx.approvedContributor();
        long s1 = fx.completeSample(a);
        mvc.perform(as(post("/api/admin/samples/" + s1 + "/approve"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("SAMPLE", Long.toString(s1)));
        mvc.perform(as(post("/api/admin/samples/" + s1 + "/void"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("SAMPLE", Long.toString(s1)));
        long s2 = fx.incompleteSample(a);
        mvc.perform(as(json(post("/api/admin/samples/" + s2 + "/return"), "{\"reason\":\"add a recording\"}")))
                .andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("SAMPLE", Long.toString(s2)));

        // Grants and the contributor's permanent exemption.
        mvc.perform(as(json(post("/api/admin/contributors/" + a + "/adfree/grants"), "{\"delta\":3,\"reason\":\"x\"}")))
                .andExpect(status().isOk());
        assertEquals("ADFREE_GRANT", lastAction("CONTRIBUTOR", a.toString()));
        assertEquals(EMAIL, lastActor("CONTRIBUTOR", a.toString()));
        mvc.perform(as(json(post("/api/admin/contributors/" + a + "/exemption"), "{\"permanent\":true}")))
                .andExpect(status().isOk());
        assertEquals("CONTRIBUTOR_EXEMPTION", lastAction("CONTRIBUTOR", a.toString()));
        assertEquals(EMAIL, lastActor("CONTRIBUTOR", a.toString()));

        // Install exemptions.
        String install = UUID.randomUUID().toString();
        mvc.perform(as(json(post("/api/admin/exemptions"), "{\"installId\":\"" + install + "\"}")))
                .andExpect(status().isCreated());
        assertEquals(EMAIL, lastActor("AD_EXEMPTION", install));
        mvc.perform(as(delete("/api/admin/exemptions/" + install))).andExpect(status().isNoContent());
        assertEquals("EXEMPTION_REMOVED", lastAction("AD_EXEMPTION", install));
        assertEquals(EMAIL, lastActor("AD_EXEMPTION", install));

        // Settings.
        mvc.perform(as(json(put("/api/admin/settings"), "{\"key\":\"credit_per_ad\",\"value\":\"2\"}")))
                .andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("SETTING", "credit_per_ad"));
        assertEquals(EMAIL, jdbc.queryForObject(
                "SELECT updated_by FROM admin_settings WHERE \"key\" = 'credit_per_ad'", String.class));
        mvc.perform(as(delete("/api/admin/settings/credit_per_ad"))).andExpect(status().isOk());
        assertEquals("SETTING_RESET", lastAction("SETTING", "credit_per_ad"));
        assertEquals(EMAIL, lastActor("SETTING", "credit_per_ad"));

        // Preliminary review.
        long s3 = fx.completeSample(a);
        mvc.perform(as(json(post("/api/admin/samples/" + s3 + "/preliminary-review"),
                "{\"recommendation\":\"FLAG_OWNER\"}"))).andExpect(status().isOk());
        assertEquals(EMAIL, lastActor("SAMPLE", Long.toString(s3)));
    }

    @Test
    void absentOrBlankHeaderFallsBackToOwner() throws Exception {
        S4Fixtures fx = fx();
        UUID c = fx.pendingContributor();
        mvc.perform(post("/api/admin/applications/" + c + "/approve")).andExpect(status().isOk());
        assertEquals("owner", lastActor("CONTRIBUTOR", c.toString()));
        mvc.perform(post("/api/admin/contributors/" + c + "/revoke").header(EMAIL_HEADER, "   "))
                .andExpect(status().isOk());
        assertEquals("owner", lastActor("CONTRIBUTOR", c.toString()));
        mvc.perform(post("/api/admin/applications/" + c + "/approve").header(EMAIL_HEADER, "  pad@example.test "))
                .andExpect(status().isOk());
        assertEquals("pad@example.test", lastActor("CONTRIBUTOR", c.toString()));

        mvc.perform(json(put("/api/admin/settings"), "{\"key\":\"initial_free_thumps\",\"value\":\"3\"}"))
                .andExpect(status().isOk());
        assertEquals("owner", lastActor("SETTING", "initial_free_thumps"));
        mvc.perform(delete("/api/admin/settings/initial_free_thumps")).andExpect(status().isOk());

        // Client-facing writes keep the contributor id as actor, header or not.
        UUID self = UUID.randomUUID();
        mvc.perform(json(post("/api/v1/contributions/applications"),
                        "{\"contributorId\":\"" + self + "\",\"note\":\"me\"}")
                        .header(BYPASS, "simulator").header(EMAIL_HEADER, EMAIL))
                .andExpect(status().isCreated());
        assertEquals(self.toString(), lastActor("CONTRIBUTOR", self.toString()));
    }

    // ---- preliminary review -------------------------------------------------------------

    @Test
    void preliminaryReviewIsStoredAuditedAndVisibleToTheAdminOnly() throws Exception {
        S4Fixtures fx = fx();
        UUID c = fx.approvedContributor();
        long id = fx.completeSample(c);
        String sid = Long.toString(id);

        JsonNode contribBefore = S4Fixtures.body(mvc.perform(get("/api/v1/contributions/samples/" + id)
                .param("contributorId", c.toString()).header(BYPASS, "simulator")).andExpect(status().isOk()));

        // Not reviewed yet: fields present in the admin shapes, null.
        JsonNode d0 = S4Fixtures.body(mvc.perform(get("/api/admin/samples/" + id)).andExpect(status().isOk()));
        assertTrue(d0.has("pepperRecommendation") && d0.get("pepperRecommendation").isNull());
        assertTrue(d0.has("pepperNote") && d0.get("pepperNote").isNull());
        assertTrue(d0.has("pepperReviewedAt") && d0.get("pepperReviewedAt").isNull());

        JsonNode r = S4Fixtures.body(mvc.perform(json(post("/api/admin/samples/" + id + "/preliminary-review"),
                        "{\"recommendation\":\"suggest_return\",\"note\":\"  cut-open photo is blurry  \"}"))
                .andExpect(status().isOk()));
        assertEquals("SUGGEST_RETURN", r.get("pepperRecommendation").asText());
        assertEquals("cut-open photo is blurry", r.get("pepperNote").asText());
        assertNotNull(r.get("pepperReviewedAt").asText());
        assertEquals("SUBMITTED", r.get("status").asText(), "advisory only: status unchanged");

        // Stored and audited, actor pepper (no Access header).
        Map<String, Object> row = jdbc.queryForMap(
                "SELECT pepper_recommendation, pepper_note, pepper_reviewed_at FROM samples WHERE id = ?", id);
        assertEquals("SUGGEST_RETURN", row.get("pepper_recommendation"));
        assertEquals("cut-open photo is blurry", row.get("pepper_note"));
        assertNotNull(row.get("pepper_reviewed_at"));
        assertEquals("PRELIMINARY_REVIEW", lastAction("SAMPLE", sid));
        assertEquals("pepper", lastActor("SAMPLE", sid));
        String after = jdbc.queryForObject("SELECT after_json FROM audit_log WHERE object_type = 'SAMPLE' "
                + "AND object_id = ? ORDER BY id DESC LIMIT 1", String.class, sid);
        assertTrue(after.contains("\"pepperRecommendation\":\"SUGGEST_RETURN\""));

        // Visible in the admin list and detail.
        JsonNode list = S4Fixtures.body(mvc.perform(get("/api/admin/samples").param("contributorId", c.toString()))
                .andExpect(status().isOk()));
        assertEquals("SUGGEST_RETURN", list.get(0).get("pepperRecommendation").asText());
        assertEquals("cut-open photo is blurry", list.get(0).get("pepperNote").asText());
        assertFalse(list.get(0).get("pepperReviewedAt").isNull());
        JsonNode d1 = S4Fixtures.body(mvc.perform(get("/api/admin/samples/" + id)).andExpect(status().isOk()));
        assertEquals("SUGGEST_RETURN", d1.get("pepperRecommendation").asText());

        // A later review replaces it; a blank note clears the note.
        mvc.perform(json(post("/api/admin/samples/" + id + "/preliminary-review"),
                        "{\"recommendation\":\"SUGGEST_APPROVE\",\"note\":\"  \"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pepperRecommendation").value("SUGGEST_APPROVE"))
                .andExpect(jsonPath("$.pepperNote").doesNotExist());

        // The owner's later decision keeps Pepper's fields (entity updates never touch them).
        mvc.perform(post("/api/admin/samples/" + id + "/approve")).andExpect(status().isOk())
                .andExpect(jsonPath("$.pepperRecommendation").value("SUGGEST_APPROVE"));

        // Contributor-facing shapes: no pepper fields, and the preliminary review did not move updatedAt.
        JsonNode contribAfter = S4Fixtures.body(mvc.perform(get("/api/v1/contributions/samples/" + id)
                .param("contributorId", c.toString()).header(BYPASS, "simulator")).andExpect(status().isOk()));
        List<String> detailFields = List.of("id", "contributorId", "status", "completeness", "complete",
                "returnReason", "variety", "weightGrams", "weightProvenance", "source", "melonDate", "feedback",
                "files", "createdAt", "updatedAt");
        assertEquals(detailFields, names(contribBefore));
        assertEquals(detailFields, names(contribAfter));
        JsonNode contribList = S4Fixtures.body(mvc.perform(get("/api/v1/contributions/samples")
                .param("contributorId", c.toString()).header(BYPASS, "simulator")).andExpect(status().isOk()));
        assertEquals(List.of("id", "status", "completeness", "complete", "returnReason", "variety", "createdAt",
                "updatedAt"), names(contribList.get(0)));
    }

    @Test
    void preliminaryReviewUpdatedAtUntouchedForContributor() throws Exception {
        S4Fixtures fx = fx();
        UUID c = fx.approvedContributor();
        long id = fx.incompleteSample(c);
        String before = jdbc.queryForObject("SELECT CAST(updated_at AS VARCHAR) FROM samples WHERE id = ?",
                String.class, id);
        mvc.perform(json(post("/api/admin/samples/" + id + "/preliminary-review"),
                "{\"recommendation\":\"FLAG_OWNER\",\"note\":\"burst of submissions\"}")).andExpect(status().isOk());
        assertEquals(before, jdbc.queryForObject("SELECT CAST(updated_at AS VARCHAR) FROM samples WHERE id = ?",
                String.class, id));
    }

    @Test
    void preliminaryReviewValidation() throws Exception {
        S4Fixtures fx = fx();
        UUID c = fx.approvedContributor();
        long id = fx.incompleteSample(c);
        String url = "/api/admin/samples/" + id + "/preliminary-review";
        int auditBefore = auditCount();

        mvc.perform(json(post("/api/admin/samples/999999/preliminary-review"), "{\"recommendation\":\"FLAG_OWNER\"}"))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.error").value("sample_not_found"));
        mvc.perform(json(post(url), "{\"recommendation\":\"APPROVE\"}")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("invalid_request"));
        mvc.perform(json(post(url), "{\"recommendation\":\"\"}")).andExpect(status().isBadRequest());
        mvc.perform(json(post(url), "{\"recommendation\":1}")).andExpect(status().isBadRequest());
        mvc.perform(json(post(url), "{\"note\":\"x\"}")).andExpect(status().isBadRequest());
        mvc.perform(json(post(url), "{\"recommendation\":\"FLAG_OWNER\",\"note\":5}")).andExpect(status().isBadRequest());
        mvc.perform(json(post(url), "{\"recommendation\":\"FLAG_OWNER\",\"note\":\"" + "n".repeat(1001) + "\"}"))
                .andExpect(status().isBadRequest());
        mvc.perform(post(url)).andExpect(status().isBadRequest());
        mvc.perform(json(post("/api/admin/samples/abc/preliminary-review"), "{\"recommendation\":\"FLAG_OWNER\"}"))
                .andExpect(status().isBadRequest());
        assertEquals(auditBefore, auditCount(), "rejected requests write nothing");

        mvc.perform(json(post(url), "{\"recommendation\":\"FLAG_OWNER\",\"note\":\"" + "n".repeat(1000) + "\"}"))
                .andExpect(status().isOk());
    }

    private static List<String> names(JsonNode n) {
        List<String> out = new ArrayList<>();
        n.fieldNames().forEachRemaining(out::add);
        return out;
    }
}

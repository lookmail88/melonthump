package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.IncentiveService;
import java.util.ArrayList;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
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
import org.springframework.test.web.servlet.ResultActions;

/**
 * S3 incentive ledger (manual grants with the zero floor, ledger read),
 * permanent contributor exemption + the status field, the client spend
 * endpoint, the install-id exemption CRUD, the version-policy
 * {@code adExempt} gating, and the audit read endpoint.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-adfree;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdFreeAndExemptionApiTest {

    static final String SPEND = "/api/v1/contributions/adfree/spend";
    static final String POLICY = "/api/v1/version/getclientversion";

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ContributionService contributions;

    @Autowired
    private IncentiveService incentives;

    private final ObjectMapper json = new ObjectMapper();

    private UUID contributor(boolean approve) {
        UUID id = UUID.randomUUID();
        contributions.submitApplication(id, "ledger test");
        if (approve) {
            contributions.approve(id, "owner");
        }
        return id;
    }

    private JsonNode body(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }

    private ResultActions postJson(String path, String content) throws Exception {
        return mvc.perform(post(path).contentType(MediaType.APPLICATION_JSON).content(content));
    }

    private ResultActions grant(UUID c, String content) throws Exception {
        return postJson("/api/admin/contributors/" + c + "/adfree/grants", content);
    }

    private ResultActions spend(UUID c) throws Exception {
        return mvc.perform(post(SPEND).header("X-Attest-Bypass", "simulator")
                .contentType(MediaType.APPLICATION_JSON).content("{\"contributorId\":\"" + c + "\"}"));
    }

    private ResultActions standing(UUID c) throws Exception {
        return mvc.perform(get("/api/v1/contributions/status").param("contributorId", c.toString())
                .header("X-Attest-Bypass", "simulator"));
    }

    private List<Map<String, Object>> audit(String objectType, String objectId) {
        return jdbc.queryForList("SELECT actor, action, before_json, after_json FROM audit_log "
                + "WHERE object_type = ? AND object_id = ? ORDER BY id", objectType, objectId);
    }

    // ---- manual grants -------------------------------------------------------------

    @Test
    void manualGrantsApplyWithZeroFloorAndAreAudited() throws Exception {
        UUID c = contributor(true);
        grant(c, "{\"delta\":7,\"reason\":\"thanks for the melons\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.contributorId").value(c.toString()))
                .andExpect(jsonPath("$.requestedDelta").value(7))
                .andExpect(jsonPath("$.appliedDelta").value(7))
                .andExpect(jsonPath("$.balance").value(7));
        grant(c, "{\"delta\":-3,\"reason\":\"correction\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.appliedDelta").value(-3)).andExpect(jsonPath("$.balance").value(4));
        // Floor: asking for -10 with 4 left applies -4.
        grant(c, "{\"delta\":-10,\"reason\":\"reset\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.requestedDelta").value(-10))
                .andExpect(jsonPath("$.appliedDelta").value(-4))
                .andExpect(jsonPath("$.balance").value(0));
        // At zero: applies 0, no ledger row.
        grant(c, "{\"delta\":-1,\"reason\":\"again\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.appliedDelta").value(0)).andExpect(jsonPath("$.balance").value(0));

        JsonNode ledger = body(mvc.perform(get("/api/admin/contributors/" + c + "/adfree")).andExpect(status().isOk()));
        assertEquals(c.toString(), ledger.get("contributorId").asText());
        assertEquals(0, ledger.get("balance").asLong());
        JsonNode entries = ledger.get("entries");
        assertEquals(3, entries.size());
        assertEquals(-4, entries.get(0).get("delta").asInt());
        assertEquals(7, entries.get(2).get("delta").asInt());
        assertEquals("ADMIN_GRANT", entries.get(0).get("reason").asText());
        assertTrue(entries.get(0).get("referenceId").isNull());
        assertTrue(entries.get(0).has("id") && entries.get(0).has("createdAt"));

        List<Map<String, Object>> rows = audit("CONTRIBUTOR", c.toString());
        List<Map<String, Object>> grants = rows.stream().filter(r -> r.get("action").equals("ADFREE_GRANT")).toList();
        assertEquals(4, grants.size());
        assertEquals("owner", grants.get(0).get("actor"));
        assertTrue(((String) grants.get(0).get("after_json")).contains("thanks for the melons"));
        assertTrue(((String) grants.get(2).get("after_json")).contains("\"appliedDelta\":-4"));
    }

    @Test
    void grantValidation() throws Exception {
        UUID c = contributor(true);
        grant(c, "{\"delta\":0,\"reason\":\"r\"}").andExpect(status().isBadRequest());
        grant(c, "{\"reason\":\"r\"}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":1.5,\"reason\":\"r\"}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":\"3\",\"reason\":\"r\"}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":3}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":3,\"reason\":\"  \"}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":3,\"reason\":\"" + "r".repeat(65) + "\"}").andExpect(status().isBadRequest());
        grant(c, "{\"delta\":3,\"reason\":\"" + "r".repeat(64) + "\"}").andExpect(status().isOk());
        grant(c, "{\"delta\":99999999999,\"reason\":\"r\"}").andExpect(status().isBadRequest());
        grant(c, "nope").andExpect(status().isBadRequest());
        grant(UUID.randomUUID(), "{\"delta\":3,\"reason\":\"r\"}").andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("contributor_not_found"));
        postJson("/api/admin/contributors/not-a-uuid/adfree/grants", "{\"delta\":3,\"reason\":\"r\"}")
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/admin/contributors/" + UUID.randomUUID() + "/adfree")).andExpect(status().isNotFound());
    }

    // ---- permanent exemption + status field ------------------------------------------

    @Test
    void permanentExemptionFlagAndStatusField() throws Exception {
        UUID c = contributor(true);
        standing(c).andExpect(jsonPath("$.adExemptPermanent").value(false));
        postJson("/api/admin/contributors/" + c + "/exemption", "{\"permanent\":true}").andExpect(status().isOk())
                .andExpect(jsonPath("$.adExemptPermanent").value(true));
        standing(c).andExpect(status().isOk()).andExpect(jsonPath("$.adExemptPermanent").value(true))
                .andExpect(jsonPath("$.adFreeBalance").value(0));
        assertEquals(1, audit("CONTRIBUTOR", c.toString()).stream()
                .filter(r -> r.get("action").equals("CONTRIBUTOR_EXEMPTION")).count());
        // Same value again: no-op, no audit row.
        postJson("/api/admin/contributors/" + c + "/exemption", "{\"permanent\":true}").andExpect(status().isOk());
        assertEquals(1, audit("CONTRIBUTOR", c.toString()).stream()
                .filter(r -> r.get("action").equals("CONTRIBUTOR_EXEMPTION")).count());
        postJson("/api/admin/contributors/" + c + "/exemption", "{\"permanent\":false}").andExpect(status().isOk())
                .andExpect(jsonPath("$.adExemptPermanent").value(false));
        standing(c).andExpect(jsonPath("$.adExemptPermanent").value(false));

        postJson("/api/admin/contributors/" + c + "/exemption", "{}").andExpect(status().isBadRequest());
        postJson("/api/admin/contributors/" + c + "/exemption", "{\"permanent\":\"yes\"}")
                .andExpect(status().isBadRequest());
        postJson("/api/admin/contributors/" + UUID.randomUUID() + "/exemption", "{\"permanent\":true}")
                .andExpect(status().isNotFound());
    }

    // ---- spend ----------------------------------------------------------------------

    @Test
    void spendSuccessInsufficientExemptAndNotApproved() throws Exception {
        UUID c = contributor(true);
        spend(c).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("insufficient_balance"));
        grant(c, "{\"delta\":2,\"reason\":\"r\"}");
        spend(c).andExpect(status().isOk()).andExpect(jsonPath("$.spent").value(true))
                .andExpect(jsonPath("$.exempt").value(false)).andExpect(jsonPath("$.balance").value(1));
        spend(c).andExpect(status().isOk()).andExpect(jsonPath("$.balance").value(0));
        spend(c).andExpect(status().isConflict());
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM ad_free_ledger WHERE contributor_id = ? "
                + "AND reason = 'SESSION_UNLOCK' AND delta = -1", Integer.class, c));
        List<Map<String, Object>> spent = audit("CONTRIBUTOR", c.toString()).stream()
                .filter(r -> r.get("action").equals("ADFREE_SPENT")).toList();
        assertEquals(2, spent.size());
        assertEquals(c.toString(), spent.get(0).get("actor"));

        // Exempt: nothing spent, balance unchanged, no ledger row.
        grant(c, "{\"delta\":3,\"reason\":\"r\"}");
        postJson("/api/admin/contributors/" + c + "/exemption", "{\"permanent\":true}");
        spend(c).andExpect(status().isOk()).andExpect(jsonPath("$.spent").value(false))
                .andExpect(jsonPath("$.exempt").value(true)).andExpect(jsonPath("$.balance").value(3));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM ad_free_ledger WHERE contributor_id = ? "
                + "AND reason = 'SESSION_UNLOCK'", Integer.class, c));
        UUID exemptZero = contributor(true);
        postJson("/api/admin/contributors/" + exemptZero + "/exemption", "{\"permanent\":true}");
        spend(exemptZero).andExpect(status().isOk()).andExpect(jsonPath("$.exempt").value(true))
                .andExpect(jsonPath("$.balance").value(0));

        UUID pending = contributor(false);
        spend(pending).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("contributor_not_approved"));
        UUID revoked = contributor(true);
        grant(revoked, "{\"delta\":3,\"reason\":\"r\"}");
        contributions.revoke(revoked, "owner");
        spend(revoked).andExpect(status().isForbidden());
        spend(UUID.randomUUID()).andExpect(status().isNotFound());

        mvc.perform(post(SPEND).header("X-Attest-Bypass", "simulator").contentType(MediaType.APPLICATION_JSON)
                .content("{}")).andExpect(status().isBadRequest());
        mvc.perform(post(SPEND).header("X-Attest-Bypass", "simulator").contentType(MediaType.APPLICATION_JSON)
                .content("{\"contributorId\":\"x\"}")).andExpect(status().isBadRequest());
        // Unattested → 401 before anything else.
        mvc.perform(post(SPEND).contentType(MediaType.APPLICATION_JSON)
                .content("{\"contributorId\":\"" + c + "\"}")).andExpect(status().isUnauthorized());
    }

    @Test
    void concurrentSpendsNeverOverdraw() throws Exception {
        UUID c = contributor(true);
        incentives.grant(c, 5, "pool", "owner");
        ExecutorService pool = Executors.newFixedThreadPool(8);
        try {
            List<Future<Boolean>> results = new ArrayList<>();
            for (int i = 0; i < 12; i++) {
                Callable<Boolean> task = () -> {
                    try {
                        return incentives.spend(c).spent();
                    } catch (IncentiveService.InsufficientBalanceException e) {
                        return false;
                    }
                };
                results.add(pool.submit(task));
            }
            int spent = 0;
            for (Future<Boolean> f : results) {
                spent += f.get() ? 1 : 0;
            }
            assertEquals(5, spent);
        } finally {
            pool.shutdown();
        }
        assertEquals(0L, jdbc.queryForObject("SELECT SUM(delta) FROM ad_free_ledger WHERE contributor_id = ?",
                Long.class, c));
    }

    // ---- install-id exemptions + policy ------------------------------------------------

    @Test
    void exemptionCrud() throws Exception {
        String install = UUID.randomUUID().toString();
        postJson("/api/admin/exemptions", "{\"installId\":\"" + install.toUpperCase() + "\",\"note\":\"owner phone\"}")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.installId").value(install))
                .andExpect(jsonPath("$.note").value("owner phone"));
        postJson("/api/admin/exemptions", "{\"installId\":\"" + install + "\",\"note\":\"owner iPad\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.note").value("owner iPad"));
        postJson("/api/admin/exemptions", "{\"installId\":\"" + install + "\",\"note\":\"owner iPad\"}")
                .andExpect(status().isOk());
        postJson("/api/admin/exemptions", "{\"installId\":\"free-form-id\"}").andExpect(status().isCreated())
                .andExpect(jsonPath("$.note").doesNotExist());

        JsonNode list = body(mvc.perform(get("/api/admin/exemptions")).andExpect(status().isOk()));
        assertTrue(list.size() >= 2);
        boolean found = false;
        for (JsonNode e : list) {
            if (e.get("installId").asText().equals(install)) {
                found = true;
                assertEquals("owner iPad", e.get("note").asText());
                assertTrue(e.has("createdAt"));
            }
        }
        assertTrue(found);
        List<Map<String, Object>> rows = audit("AD_EXEMPTION", install);
        assertEquals(2, rows.size());
        assertEquals("EXEMPTION_SET", rows.get(0).get("action"));

        postJson("/api/admin/exemptions", "{}").andExpect(status().isBadRequest());
        postJson("/api/admin/exemptions", "{\"installId\":\"  \"}").andExpect(status().isBadRequest());
        postJson("/api/admin/exemptions", "{\"installId\":\"" + "i".repeat(65) + "\"}").andExpect(status().isBadRequest());
        postJson("/api/admin/exemptions", "{\"installId\":\"a\",\"note\":\"" + "n".repeat(129) + "\"}")
                .andExpect(status().isBadRequest());

        mvc.perform(delete("/api/admin/exemptions/" + install.toUpperCase())).andExpect(status().isNoContent());
        assertEquals("EXEMPTION_REMOVED", audit("AD_EXEMPTION", install).get(2).get("action"));
        mvc.perform(delete("/api/admin/exemptions/" + install)).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("exemption_not_found"));
        mvc.perform(delete("/api/admin/exemptions/free-form-id")).andExpect(status().isNoContent());
    }

    @Test
    void policyAdExemptIsGatedToTwoPointOh() throws Exception {
        String install = UUID.randomUUID().toString();
        postJson("/api/admin/exemptions", "{\"installId\":\"" + install + "\"}").andExpect(status().isCreated());

        // 2.0.0+: true on a match (case-insensitive UUID), false otherwise or without the header.
        mvc.perform(get(POLICY).param("currentVersion", "2.0.0").header("X-Install-Id", install))
                .andExpect(status().isOk()).andExpect(jsonPath("$.adExempt").value(true));
        mvc.perform(get(POLICY).param("currentVersion", "2.1.3").header("X-Install-Id", install.toUpperCase()))
                .andExpect(jsonPath("$.adExempt").value(true));
        mvc.perform(get(POLICY).param("currentVersion", "2.0.0").header("X-Install-Id", UUID.randomUUID().toString()))
                .andExpect(jsonPath("$.adExempt").value(false));
        mvc.perform(get(POLICY).param("currentVersion", "2.0.0"))
                .andExpect(jsonPath("$.adExempt").value(false))
                .andExpect(jsonPath("$.initialFreeThumps").value(2));
        mvc.perform(get(POLICY).param("currentVersion", "2.0.0").header("X-Install-Id", "x".repeat(200)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.adExempt").value(false));

        // Older clients: header ignored, response byte-identical to today's.
        for (String v : new String[] {"1.0.0", "1.1.0", "1.9.9"}) {
            String plain = mvc.perform(get(POLICY).param("currentVersion", v))
                    .andReturn().getResponse().getContentAsString();
            String withHeader = mvc.perform(get(POLICY).param("currentVersion", v).header("X-Install-Id", install))
                    .andReturn().getResponse().getContentAsString();
            assertEquals(plain, withHeader);
            assertFalse(withHeader.contains("adExempt"));
        }
        assertEquals(String.format(VersionPolicyAllowanceTest.LEGACY_BODY_TEMPLATE, false, false),
                mvc.perform(get(POLICY).param("currentVersion", "1.1.0").header("X-Install-Id", install))
                        .andReturn().getResponse().getContentAsString());
        assertEquals(String.format(VersionPolicyAllowanceTest.LEGACY_BODY_TEMPLATE, false, false),
                mvc.perform(get(POLICY).header("X-Install-Id", install))
                        .andReturn().getResponse().getContentAsString());
        // The 1.2.0 response is exactly today's 1.2.0 response (no adExempt, header ignored).
        String v12 = mvc.perform(get(POLICY).param("currentVersion", "1.2.0").header("X-Install-Id", install))
                .andReturn().getResponse().getContentAsString();
        assertEquals("{\"platform\":\"ios\",\"latestVersion\":\"1.0.0\",\"minSupportedVersion\":\"1.0.0\","
                + "\"updateAvailable\":false,\"forceUpdate\":false,"
                + "\"updateUrl\":\"https://apps.apple.com/us/app/melonthump/id6825623861\",\"creditPerAd\":1,"
                + "\"promoEndsAtEpochMillis\":null,\"initialFreeThumps\":2,\"sessionUnlockEnabled\":true,"
                + "\"adFreeSessionCreditPrice\":1}", v12);
    }

    // ---- audit read ---------------------------------------------------------------------

    @Test
    void auditReadFiltersNewestFirstAndLimits() throws Exception {
        UUID c = contributor(true);
        grant(c, "{\"delta\":1,\"reason\":\"a\"}");
        grant(c, "{\"delta\":2,\"reason\":\"b\"}");
        JsonNode rows = body(mvc.perform(get("/api/admin/audit").param("objectType", "CONTRIBUTOR")
                .param("objectId", c.toString())).andExpect(status().isOk()));
        assertEquals(4, rows.size()); // submitted, approved, grant, grant
        assertEquals("ADFREE_GRANT", rows.get(0).get("action").asText());
        assertTrue(rows.get(0).get("afterJson").asText().contains("\"reason\":\"b\""));
        assertEquals("APPLICATION_SUBMITTED", rows.get(3).get("action").asText());
        assertTrue(rows.get(3).get("beforeJson").isNull());
        assertTrue(rows.get(0).get("id").asLong() > rows.get(1).get("id").asLong());
        JsonNode first = rows.get(0);
        for (String f : new String[] {"id", "actor", "action", "objectType", "objectId", "beforeJson", "afterJson",
                "createdAt"}) {
            assertTrue(first.has(f), f);
        }

        JsonNode limited = body(mvc.perform(get("/api/admin/audit").param("objectId", c.toString())
                .param("limit", "2")));
        assertEquals(2, limited.size());
        JsonNode byType = body(mvc.perform(get("/api/admin/audit").param("objectType", "CONTRIBUTOR")));
        for (JsonNode r : byType) {
            assertEquals("CONTRIBUTOR", r.get("objectType").asText());
        }
        assertTrue(byType.size() <= 50);
        JsonNode none = body(mvc.perform(get("/api/admin/audit").param("objectType", "NOPE")));
        assertEquals(0, none.size());
        JsonNode all = body(mvc.perform(get("/api/admin/audit").param("limit", "500")).andExpect(status().isOk()));
        assertTrue(all.size() >= 4 && all.size() <= 200);
        mvc.perform(get("/api/admin/audit").param("limit", "-5")).andExpect(status().isBadRequest());
    }
}

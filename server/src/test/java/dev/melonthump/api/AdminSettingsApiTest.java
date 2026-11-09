package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import dev.melonthump.contrib.ContributionService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
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
 * S4 runtime settings: CRUD + per-key validation, audit rows, and the
 * consumer wiring — the version policy VALUES follow an override and
 * revert on DELETE while every response shape (and the per-version
 * gating) stays exactly as before; an approved complete sample earns the
 * overridden unit count. The settings snapshot cache is disabled here so
 * direct table cleanup between tests is seen immediately.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:melonthump-s4-settings;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "melonthump.admin.settings-cache-millis=0"})
class AdminSettingsApiTest {

    static final String SETTINGS = "/api/admin/settings";
    static final String POLICY = "/api/v1/version/getclientversion";

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ContributionService contributions;

    @AfterEach
    void clearOverrides() {
        jdbc.update("DELETE FROM admin_settings");
    }

    private ResultActions putSetting(String rawBody) throws Exception {
        return mvc.perform(put(SETTINGS).contentType(MediaType.APPLICATION_JSON).content(rawBody));
    }

    private ResultActions putSetting(String key, String value) throws Exception {
        return putSetting("{\"key\":\"" + key + "\",\"value\":\"" + value + "\"}");
    }

    private JsonNode setting(String key) throws Exception {
        JsonNode all = S4Fixtures.body(mvc.perform(get(SETTINGS)).andExpect(status().isOk()));
        for (JsonNode s : all) {
            if (s.get("key").asText().equals(key)) {
                return s;
            }
        }
        throw new AssertionError("no setting " + key);
    }

    private String policy(String currentVersion) throws Exception {
        var r = get(POLICY);
        if (currentVersion != null) {
            r = r.param("currentVersion", currentVersion);
        }
        return mvc.perform(r).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
    }

    private static String legacyBody(int creditPerAd, String promo) {
        return "{\"platform\":\"ios\",\"latestVersion\":\"1.0.0\","
                + "\"minSupportedVersion\":\"1.0.0\",\"updateAvailable\":false,\"forceUpdate\":false,"
                + "\"updateUrl\":\"https://apps.apple.com/us/app/melonthump/id6825623861\","
                + "\"creditPerAd\":" + creditPerAd + ",\"promoEndsAtEpochMillis\":" + promo + "}";
    }

    // ---- read ------------------------------------------------------------------

    @Test
    void listsExactlyTheFourKnownKeysWithDefaults() throws Exception {
        JsonNode all = S4Fixtures.body(mvc.perform(get(SETTINGS)).andExpect(status().isOk()));
        assertEquals(4, all.size());
        assertEquals("adfree_per_approved_sample", all.get(0).get("key").asText());
        assertEquals("promo_ends_at_epoch_millis", all.get(1).get("key").asText());
        assertEquals("initial_free_thumps", all.get(2).get("key").asText());
        assertEquals("credit_per_ad", all.get(3).get("key").asText());
        for (JsonNode s : all) {
            assertEquals(List.of("key", "value", "defaultValue", "overridden"),
                    iterable(s.fieldNames()));
            assertFalse(s.get("overridden").asBoolean());
        }
        assertEquals("5", all.get(0).get("value").asText());
        assertEquals("5", all.get(0).get("defaultValue").asText());
        assertTrue(all.get(1).get("value").isNull(), "no promo configured under the test profile");
        assertTrue(all.get(1).get("defaultValue").isNull());
        assertEquals("2", all.get(2).get("value").asText());
        assertEquals("1", all.get(3).get("value").asText());
    }

    private static List<String> iterable(java.util.Iterator<String> it) {
        List<String> out = new java.util.ArrayList<>();
        it.forEachRemaining(out::add);
        return out;
    }

    // ---- validation --------------------------------------------------------------

    @Test
    void validatesEveryKeyAndRejectsUnknownKeys() throws Exception {
        putSetting("latest_version", "9.9.9").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("invalid_request"));
        putSetting("min_supported_version", "9.9.9").andExpect(status().isBadRequest());
        putSetting("bogus", "1").andExpect(status().isBadRequest());

        putSetting("adfree_per_approved_sample", "-1").andExpect(status().isBadRequest());
        putSetting("adfree_per_approved_sample", "1.5").andExpect(status().isBadRequest());
        putSetting("adfree_per_approved_sample", "x").andExpect(status().isBadRequest());
        putSetting("adfree_per_approved_sample", "").andExpect(status().isBadRequest());
        putSetting("adfree_per_approved_sample", "99999999999").andExpect(status().isBadRequest());
        putSetting("promo_ends_at_epoch_millis", "-5").andExpect(status().isBadRequest());
        putSetting("promo_ends_at_epoch_millis", "abc").andExpect(status().isBadRequest());
        putSetting("initial_free_thumps", "-1").andExpect(status().isBadRequest());
        putSetting("credit_per_ad", "-2").andExpect(status().isBadRequest());
        putSetting("credit_per_ad", "one").andExpect(status().isBadRequest());

        putSetting("{\"key\":\"credit_per_ad\"}").andExpect(status().isBadRequest());
        putSetting("{\"key\":\"credit_per_ad\",\"value\":true}").andExpect(status().isBadRequest());
        putSetting("{\"value\":\"1\"}").andExpect(status().isBadRequest());
        putSetting("not json").andExpect(status().isBadRequest());
        mvc.perform(put(SETTINGS)).andExpect(status().isBadRequest());

        // Nothing was written by any rejected request.
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM admin_settings", Integer.class));

        // Boundary values that are valid; a JSON integer value is accepted too.
        putSetting("credit_per_ad", "-1").andExpect(status().isOk()).andExpect(jsonPath("$.value").value("-1"));
        putSetting("credit_per_ad", " 0 ").andExpect(status().isOk()).andExpect(jsonPath("$.value").value("0"));
        putSetting("{\"key\":\"initial_free_thumps\",\"value\":0}").andExpect(status().isOk())
                .andExpect(jsonPath("$.value").value("0"));
        putSetting("promo_ends_at_epoch_millis", "0").andExpect(status().isOk());
        putSetting("adfree_per_approved_sample", "0").andExpect(status().isOk());
    }

    // ---- write / reset + audit ----------------------------------------------------

    @Test
    void putOverridesAndDeleteRevertsWithAuditRows() throws Exception {
        long auditMark = jdbc.queryForObject("SELECT COALESCE(MAX(id), 0) FROM audit_log", Long.class);
        putSetting("adfree_per_approved_sample", "8").andExpect(status().isOk())
                .andExpect(jsonPath("$.key").value("adfree_per_approved_sample"))
                .andExpect(jsonPath("$.value").value("8"))
                .andExpect(jsonPath("$.defaultValue").value("5"))
                .andExpect(jsonPath("$.overridden").value(true));
        JsonNode s = setting("adfree_per_approved_sample");
        assertEquals("8", s.get("value").asText());
        assertTrue(s.get("overridden").asBoolean());

        putSetting("adfree_per_approved_sample", "9").andExpect(status().isOk());
        Map<String, Object> row = jdbc.queryForMap(
                "SELECT \"value\", updated_by, updated_at FROM admin_settings WHERE \"key\" = 'adfree_per_approved_sample'");
        assertEquals("9", row.get("value"));
        assertEquals("owner", row.get("updated_by"));

        mvc.perform(delete(SETTINGS + "/adfree_per_approved_sample")).andExpect(status().isOk())
                .andExpect(jsonPath("$.value").value("5"))
                .andExpect(jsonPath("$.overridden").value(false));
        assertFalse(setting("adfree_per_approved_sample").get("overridden").asBoolean());
        mvc.perform(delete(SETTINGS + "/adfree_per_approved_sample")).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("setting_not_overridden"));
        mvc.perform(delete(SETTINGS + "/latest_version")).andExpect(status().isBadRequest());

        List<Map<String, Object>> audit = jdbc.queryForList("SELECT actor, action, before_json, after_json "
                + "FROM audit_log WHERE object_type = 'SETTING' AND object_id = 'adfree_per_approved_sample' AND id > ? "
                + "ORDER BY id", auditMark);
        assertEquals(3, audit.size());
        assertEquals("SETTING_CHANGED", audit.get(0).get("action"));
        assertEquals("owner", audit.get(0).get("actor"));
        assertTrue(((String) audit.get(0).get("before_json")).contains("\"value\":\"5\""));
        assertTrue(((String) audit.get(0).get("before_json")).contains("\"overridden\":false"));
        assertTrue(((String) audit.get(0).get("after_json")).contains("\"value\":\"8\""));
        assertTrue(((String) audit.get(1).get("before_json")).contains("\"value\":\"8\""));
        assertTrue(((String) audit.get(1).get("after_json")).contains("\"value\":\"9\""));
        assertEquals("SETTING_RESET", audit.get(2).get("action"));
        assertTrue(((String) audit.get(2).get("before_json")).contains("\"value\":\"9\""));
        assertTrue(((String) audit.get(2).get("after_json")).contains("\"value\":\"5\""));
    }

    // ---- consumer wiring: version policy -------------------------------------------

    @Test
    void policyValuesFollowOverridesAndShapesStayTheSame() throws Exception {
        String legacyDefault = legacyBody(1, "null");
        assertEquals(legacyDefault, policy(null));
        assertEquals(legacyDefault, policy("1.1.0"));
        String modernBefore = policy("1.2.0");
        String v2Before = policy("2.0.0");

        putSetting("credit_per_ad", "-1").andExpect(status().isOk());
        putSetting("promo_ends_at_epoch_millis", "1767225599000").andExpect(status().isOk());
        putSetting("initial_free_thumps", "4").andExpect(status().isOk());

        // Legacy clients: identical shape, only the two existing values changed; no 1.2.0 field leaks.
        String legacyNow = legacyBody(-1, "1767225599000");
        assertEquals(legacyNow, policy(null));
        assertEquals(legacyNow, policy("1.0.0"));
        assertEquals(legacyNow, policy("1.1.0"));

        // 1.2.0 / 2.0.0 clients: same field set as before, new values.
        String modern = policy("1.2.0");
        assertEquals(fieldNames(modernBefore), fieldNames(modern));
        JsonNode m = S4Fixtures.JSON.readTree(modern);
        assertEquals(-1, m.get("creditPerAd").asInt());
        assertEquals(1767225599000L, m.get("promoEndsAtEpochMillis").asLong());
        assertEquals(4, m.get("initialFreeThumps").asInt());
        assertFalse(m.has("adExempt"), "adExempt stays 2.0.0+ only");
        String v2 = policy("2.0.0");
        assertEquals(fieldNames(v2Before), fieldNames(v2));
        assertEquals(4, S4Fixtures.JSON.readTree(v2).get("initialFreeThumps").asInt());
        assertTrue(S4Fixtures.JSON.readTree(v2).has("adExempt"));

        // Release-class numbers are untouched by any setting.
        assertEquals("1.0.0", m.get("latestVersion").asText());
        assertEquals("1.0.0", m.get("minSupportedVersion").asText());

        // DELETE reverts every value; responses are byte-identical to before.
        mvc.perform(delete(SETTINGS + "/credit_per_ad")).andExpect(status().isOk());
        mvc.perform(delete(SETTINGS + "/promo_ends_at_epoch_millis")).andExpect(status().isOk());
        mvc.perform(delete(SETTINGS + "/initial_free_thumps")).andExpect(status().isOk());
        assertEquals(legacyDefault, policy("1.1.0"));
        assertEquals(modernBefore, policy("1.2.0"));
        assertEquals(v2Before, policy("2.0.0"));
    }

    private static List<String> fieldNames(String json) throws Exception {
        return iterable(S4Fixtures.JSON.readTree(json).fieldNames());
    }

    // ---- consumer wiring: incentive ledger -------------------------------------------

    @Test
    void approvedSampleEarnsTheOverriddenUnitCount() throws Exception {
        S4Fixtures fx = new S4Fixtures(mvc, contributions);
        UUID c = fx.approvedContributor();
        putSetting("adfree_per_approved_sample", "7").andExpect(status().isOk());
        long first = fx.completeSample(c);
        mvc.perform(post("/api/admin/samples/" + first + "/approve")).andExpect(status().isOk());
        assertEquals(7L, balance(c));
        assertTrue(lastSampleAudit(first).contains("\"grantedUnits\":7"));

        mvc.perform(delete(SETTINGS + "/adfree_per_approved_sample")).andExpect(status().isOk());
        long second = fx.completeSample(c);
        mvc.perform(post("/api/admin/samples/" + second + "/approve")).andExpect(status().isOk());
        assertEquals(12L, balance(c), "back to the default 5 after the reset");

        putSetting("adfree_per_approved_sample", "0").andExpect(status().isOk());
        long third = fx.completeSample(c);
        mvc.perform(post("/api/admin/samples/" + third + "/approve")).andExpect(status().isOk());
        assertEquals(12L, balance(c), "0 units: approval earns nothing");
    }

    private long balance(UUID c) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(delta), 0) FROM ad_free_ledger WHERE contributor_id = ?",
                Long.class, c);
    }

    private String lastSampleAudit(long sampleId) {
        List<String> rows = jdbc.queryForList("SELECT after_json FROM audit_log WHERE object_type = 'SAMPLE' "
                + "AND object_id = ? ORDER BY id DESC", String.class, Long.toString(sampleId));
        return rows.get(0);
    }
}

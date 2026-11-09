package dev.melonthump.api;

import static dev.melonthump.api.SampleApiTest.file;
import static dev.melonthump.api.SampleApiTest.meta;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.ContributionService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockPart;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;

/**
 * S3 owner sample review: list / detail / material download, the review
 * state machine (approve / return / void incl. no-op repeats and 409s),
 * return-reason validation, the grant on approval (complete only, exactly
 * once) and the void clawback math (full, partial, already clawed back).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-admin-review;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdminReviewApiTest {

    static final String ADMIN = "/api/admin/samples";

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ContributionService contributions;

    private final ObjectMapper json = new ObjectMapper();

    // ---- fixtures ------------------------------------------------------------

    private UUID approvedContributor() {
        UUID id = UUID.randomUUID();
        contributions.submitApplication(id, "reviewer test");
        contributions.approve(id, "owner");
        return id;
    }

    static byte[] bytes(int n, int seed) {
        byte[] b = new byte[n];
        for (int i = 0; i < n; i++) {
            b[i] = (byte) (i * 7 + seed);
        }
        return b;
    }

    private ResultActions submit(MockPart... parts) throws Exception {
        MockMultipartHttpServletRequestBuilder b = multipart(SampleApiTest.BASE);
        for (MockPart p : parts) {
            b.part(p);
        }
        return mvc.perform(b.header("X-Attest-Bypass", "simulator"));
    }

    private Map<String, Object> metaMap(UUID c, boolean withFeedback) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", c.toString());
        m.put("variety", "KIRIN");
        if (withFeedback) {
            Map<String, Object> f = new LinkedHashMap<>();
            f.put("score", 80);
            f.put("tasteTags", List.of("CRISP"));
            f.put("bandTruth", "RIPE");
            m.put("feedback", f);
        }
        return m;
    }

    private long completeSample(UUID c) throws Exception {
        return body(submit(meta(metaMap(c, true)),
                file("appearance", "a.jpg", "image/jpeg", bytes(300, 1)),
                file("recording", "r.m4a", "audio/m4a", bytes(500, 2)),
                file("cutOpen", "c.png", "image/png", bytes(400, 3)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.complete").value(true))).get("id").asLong();
    }

    private long incompleteSample(UUID c) throws Exception {
        return body(submit(meta(metaMap(c, false)), file("appearance", "a.jpg", "image/jpeg", bytes(200, 9)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.complete").value(false))).get("id").asLong();
    }

    private JsonNode body(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }

    private ResultActions approve(long id) throws Exception {
        return mvc.perform(post(ADMIN + "/" + id + "/approve"));
    }

    private ResultActions returnWith(long id, String rawBody) throws Exception {
        var b = post(ADMIN + "/" + id + "/return");
        if (rawBody != null) {
            b = b.contentType(MediaType.APPLICATION_JSON).content(rawBody);
        }
        return mvc.perform(b);
    }

    private ResultActions voidIt(long id) throws Exception {
        return mvc.perform(post(ADMIN + "/" + id + "/void"));
    }

    private long balance(UUID c) {
        return jdbc.queryForObject("SELECT COALESCE(SUM(delta), 0) FROM ad_free_ledger WHERE contributor_id = ?",
                Long.class, c);
    }

    private List<Map<String, Object>> ledgerRows(long sampleId) {
        return jdbc.queryForList("SELECT delta, reason FROM ad_free_ledger WHERE reference_id = ? ORDER BY id",
                Long.toString(sampleId));
    }

    private List<Map<String, Object>> audit(long sampleId) {
        return jdbc.queryForList("SELECT actor, action, before_json, after_json FROM audit_log "
                + "WHERE object_type = 'SAMPLE' AND object_id = ? ORDER BY id", Long.toString(sampleId));
    }

    private void spend(UUID c, int times) throws Exception {
        for (int i = 0; i < times; i++) {
            mvc.perform(post("/api/v1/contributions/adfree/spend").header("X-Attest-Bypass", "simulator")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"contributorId\":\"" + c + "\"}"))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.spent").value(true));
        }
    }

    // ---- list / detail / download -------------------------------------------------

    @Test
    void listFiltersAndOrdersNewestFirst() throws Exception {
        UUID a = approvedContributor();
        UUID b = approvedContributor();
        long a1 = incompleteSample(a);
        long a2 = completeSample(a);
        long b1 = incompleteSample(b);
        approve(a2).andExpect(status().isOk());

        JsonNode mine = body(mvc.perform(get(ADMIN).param("contributorId", a.toString())).andExpect(status().isOk()));
        assertEquals(2, mine.size());
        assertEquals(a2, mine.get(0).get("id").asLong());
        assertEquals(a1, mine.get(1).get("id").asLong());
        JsonNode first = mine.get(0);
        assertEquals(a.toString(), first.get("contributorId").asText());
        assertEquals("APPROVED", first.get("status").asText());
        assertTrue(first.get("complete").asBoolean());
        assertTrue(first.get("completeness").get("cutOpen").asBoolean());
        assertEquals("KIRIN", first.get("variety").asText());
        assertTrue(first.has("createdAt") && first.has("updatedAt"));

        JsonNode approved = body(mvc.perform(get(ADMIN).param("status", "approved")
                .param("contributorId", a.toString())).andExpect(status().isOk()));
        assertEquals(1, approved.size());
        JsonNode submittedB = body(mvc.perform(get(ADMIN).param("status", "SUBMITTED")
                .param("contributorId", b.toString())));
        assertEquals(b1, submittedB.get(0).get("id").asLong());

        JsonNode all = body(mvc.perform(get(ADMIN).param("limit", "1")).andExpect(status().isOk()));
        assertEquals(1, all.size());
        assertEquals(b1, all.get(0).get("id").asLong());
        mvc.perform(get(ADMIN).param("limit", "100000")).andExpect(status().isOk());

        mvc.perform(get(ADMIN).param("status", "BOGUS")).andExpect(status().isBadRequest());
        mvc.perform(get(ADMIN).param("contributorId", "nope")).andExpect(status().isBadRequest());
        mvc.perform(get(ADMIN).param("limit", "0")).andExpect(status().isBadRequest());
        mvc.perform(get(ADMIN).param("limit", "x")).andExpect(status().isBadRequest());
    }

    @Test
    void detailAndMaterialDownload() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        JsonNode d = body(mvc.perform(get(ADMIN + "/" + id)).andExpect(status().isOk()));
        assertEquals(c.toString(), d.get("contributorId").asText());
        assertEquals("SUBMITTED", d.get("status").asText());
        assertEquals(80, d.get("feedback").get("score").asInt());
        assertEquals(3, d.get("files").size());
        JsonNode cut = null;
        for (JsonNode f : d.get("files")) {
            assertTrue(f.has("id") && f.has("sha256") && !f.has("storedPath"));
            if (f.get("part").asText().equals("CUT_OPEN")) {
                cut = f;
            }
        }
        long fileId = cut.get("id").asLong();
        byte[] got = mvc.perform(get(ADMIN + "/" + id + "/files/" + fileId))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "image/png"))
                .andReturn().getResponse().getContentAsByteArray();
        assertArrayEquals(bytes(400, 3), got);

        // A file of another sample, unknown ids, malformed ids.
        long other = completeSample(c);
        mvc.perform(get(ADMIN + "/" + other + "/files/" + fileId)).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("file_not_found"));
        mvc.perform(get(ADMIN + "/" + id + "/files/999999")).andExpect(status().isNotFound());
        mvc.perform(get(ADMIN + "/999999/files/" + fileId)).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("sample_not_found"));
        mvc.perform(get(ADMIN + "/999999")).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("sample_not_found"));
        mvc.perform(get(ADMIN + "/abc")).andExpect(status().isBadRequest());
        mvc.perform(get(ADMIN + "/" + id + "/files/abc")).andExpect(status().isBadRequest());
    }

    // ---- state machine -----------------------------------------------------------

    @Test
    void approveGrantsOnceForCompleteSampleAndRepeatIsNoOp() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        approve(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("APPROVED"));
        assertEquals(5, balance(c));
        List<Map<String, Object>> rows = ledgerRows(id);
        assertEquals(1, rows.size());
        assertEquals("SAMPLE_APPROVED", rows.get(0).get("reason"));
        assertEquals(5, ((Number) rows.get(0).get("delta")).intValue());
        int auditRows = audit(id).size();
        Map<String, Object> last = audit(id).get(auditRows - 1);
        assertEquals("owner", last.get("actor"));
        assertEquals("SAMPLE_APPROVED", last.get("action"));
        assertTrue(((String) last.get("after_json")).contains("\"grantedUnits\":5"));
        assertTrue(((String) last.get("before_json")).contains("\"status\":\"SUBMITTED\""));

        approve(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("APPROVED"));
        assertEquals(5, balance(c));
        assertEquals(1, ledgerRows(id).size());
        assertEquals(auditRows, audit(id).size());

        // Approved samples cannot be returned; contributor append/withdraw are now 409 (S2 paths).
        returnWith(id, "{\"reason\":\"x\"}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("illegal_sample_state"));
    }

    @Test
    void approvingAnIncompleteSampleEarnsNothing() throws Exception {
        UUID c = approvedContributor();
        long id = incompleteSample(c);
        approve(id).andExpect(status().isOk());
        assertEquals(0, balance(c));
        assertTrue(ledgerRows(id).isEmpty());
        assertTrue(((String) audit(id).get(audit(id).size() - 1).get("after_json")).contains("\"grantedUnits\":0"));
    }

    @Test
    void returnRequiresReasonAndFollowsStateMachine() throws Exception {
        UUID c = approvedContributor();
        long id = incompleteSample(c);
        returnWith(id, null).andExpect(status().isBadRequest());
        returnWith(id, "").andExpect(status().isBadRequest());
        returnWith(id, "{}").andExpect(status().isBadRequest());
        returnWith(id, "{\"reason\":\"   \"}").andExpect(status().isBadRequest());
        returnWith(id, "{\"reason\":null}").andExpect(status().isBadRequest());
        returnWith(id, "{\"reason\":42}").andExpect(status().isBadRequest());
        returnWith(id, "not json").andExpect(status().isBadRequest());
        returnWith(id, "{\"reason\":\"" + "x".repeat(501) + "\"}").andExpect(status().isBadRequest());
        assertEquals(1, audit(id).size());

        String reason = "y".repeat(500);
        returnWith(id, "{\"reason\":\"  " + reason + "  \"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("RETURNED"))
                .andExpect(jsonPath("$.returnReason").value(reason));
        Map<String, Object> row = audit(id).get(1);
        assertEquals("SAMPLE_RETURNED", row.get("action"));
        assertTrue(((String) row.get("after_json")).contains(reason));

        // Repeat: no-op, reason unchanged, no audit row.
        returnWith(id, "{\"reason\":\"other\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.returnReason").value(reason));
        assertEquals(2, audit(id).size());

        // Approving a RETURNED sample is refused.
        approve(id).andExpect(status().isConflict());

        // Contributor sees the reason and resubmits via append (S2 path, now reachable end-to-end).
        mvc.perform(get(SampleApiTest.BASE + "/" + id).param("contributorId", c.toString())
                        .header("X-Attest-Bypass", "simulator"))
                .andExpect(jsonPath("$.status").value("RETURNED"))
                .andExpect(jsonPath("$.returnReason").value(reason));
        MockMultipartHttpServletRequestBuilder b = multipart(SampleApiTest.BASE + "/" + id + "/parts?contributorId=" + c);
        b.part(file("recording", "r.wav", "audio/wav", bytes(100, 4)));
        mvc.perform(b.header("X-Attest-Bypass", "simulator")).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SUBMITTED"))
                .andExpect(jsonPath("$.returnReason").doesNotExist());
        approve(id).andExpect(status().isOk());
    }

    @Test
    void voidFromEveryOpenStateAndRepeatIsNoOp() throws Exception {
        UUID c = approvedContributor();
        long submitted = incompleteSample(c);
        long returned = incompleteSample(c);
        returnWith(returned, "{\"reason\":\"blurry\"}").andExpect(status().isOk());
        long approved = incompleteSample(c);
        approve(approved).andExpect(status().isOk());

        for (long id : new long[] {submitted, returned, approved}) {
            voidIt(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("VOIDED"));
            int n = audit(id).size();
            assertEquals("SAMPLE_VOIDED", audit(id).get(n - 1).get("action"));
            voidIt(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("VOIDED"));
            assertEquals(n, audit(id).size());
            approve(id).andExpect(status().isConflict());
            returnWith(id, "{\"reason\":\"x\"}").andExpect(status().isConflict());
        }
        // Void-marking keeps the row and its materials.
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM sample_files WHERE sample_id = ?",
                Integer.class, submitted));
        mvc.perform(post(ADMIN + "/424242/void")).andExpect(status().isNotFound());
        mvc.perform(post(ADMIN + "/-1/approve")).andExpect(status().isBadRequest());
        mvc.perform(post(ADMIN + "/x/return").contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"r\"}"))
                .andExpect(status().isBadRequest());
    }

    // ---- clawback ----------------------------------------------------------------

    @Test
    void voidClawsBackFullEarningWhenBalanceAllows() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        approve(id);
        mvc.perform(post("/api/admin/contributors/" + c + "/adfree/grants").contentType(MediaType.APPLICATION_JSON)
                .content("{\"delta\":3,\"reason\":\"bonus\"}")).andExpect(status().isOk());
        assertEquals(8, balance(c));
        voidIt(id).andExpect(status().isOk());
        assertEquals(3, balance(c));
        List<Map<String, Object>> rows = ledgerRows(id);
        assertEquals(2, rows.size());
        assertEquals("VOID_CLAWBACK", rows.get(1).get("reason"));
        assertEquals(-5, ((Number) rows.get(1).get("delta")).intValue());
        String after = (String) audit(id).get(audit(id).size() - 1).get("after_json");
        assertTrue(after.contains("\"earnedUnits\":5") && after.contains("\"clawedBackUnits\":5"));
    }

    @Test
    void voidClawsBackOnlyTheUnusedBalance() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        approve(id);
        spend(c, 3);
        assertEquals(2, balance(c));
        voidIt(id).andExpect(status().isOk());
        assertEquals(0, balance(c));
        assertEquals(-2, ((Number) ledgerRows(id).get(1).get("delta")).intValue());

        // Balance already zero: nothing left to claw back, no ledger row, never negative.
        UUID d = approvedContributor();
        long id2 = completeSample(d);
        approve(id2);
        spend(d, 5);
        voidIt(id2).andExpect(status().isOk());
        assertEquals(0, balance(d));
        assertEquals(1, ledgerRows(id2).size());
        assertTrue(((String) audit(id2).get(audit(id2).size() - 1).get("after_json"))
                .contains("\"clawedBackUnits\":0"));
    }

    @Test
    void alreadyClawedBackSampleIsNotClawedTwice() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        approve(id);
        mvc.perform(post("/api/admin/contributors/" + c + "/adfree/grants").contentType(MediaType.APPLICATION_JSON)
                .content("{\"delta\":10,\"reason\":\"bonus\"}")).andExpect(status().isOk());
        // A clawback row already exists for this sample (e.g. recorded by an earlier operation).
        jdbc.update("INSERT INTO ad_free_ledger (contributor_id, delta, reason, reference_id) VALUES (?, -5, "
                + "'VOID_CLAWBACK', ?)", c, Long.toString(id));
        assertEquals(10, balance(c));
        voidIt(id).andExpect(status().isOk());
        assertEquals(10, balance(c));
        assertEquals(2, ledgerRows(id).size());
    }

    @Test
    void reviewActionsWithoutEarningLeaveLedgerUntouched() throws Exception {
        UUID c = approvedContributor();
        long id = completeSample(c);
        returnWith(id, "{\"reason\":\"redo\"}");
        voidIt(id).andExpect(status().isOk());
        assertTrue(ledgerRows(id).isEmpty());
        assertNull(jdbc.queryForObject("SELECT MAX(id) FROM ad_free_ledger WHERE contributor_id = ?",
                Long.class, c));
    }

    // ---- FIX12: Vision watermelon annotation ------------------------------------

    @Test
    void visionScoresArePersistedOptionalValidatedAndShownInAdminDetail() throws Exception {
        UUID c = approvedContributor();

        // Absent (older clients): both null.
        long plain = incompleteSample(c);
        mvc.perform(get(ADMIN + "/" + plain)).andExpect(status().isOk())
                .andExpect(jsonPath("$.visionWatermelon").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.visionCutopenWatermelon").value(org.hamcrest.Matchers.nullValue()));

        // Present on submit: persisted and exposed; explicit null = absent.
        Map<String, Object> m = metaMap(c, false);
        m.put("visionWatermelon", 0.87);
        m.put("visionCutopenWatermelon", null);
        long id = body(submit(meta(m), file("appearance", "a.jpg", "image/jpeg", bytes(200, 4)))
                .andExpect(status().isCreated())).get("id").asLong();
        mvc.perform(get(ADMIN + "/" + id)).andExpect(status().isOk())
                .andExpect(jsonPath("$.visionWatermelon").value(0.87))
                .andExpect(jsonPath("$.visionCutopenWatermelon").value(org.hamcrest.Matchers.nullValue()));
        assertEquals(0.87, jdbc.queryForObject("SELECT vision_watermelon FROM samples WHERE id = ?",
                Double.class, id), 1e-9);

        // Append: a sent score overwrites, an absent one is kept.
        Map<String, Object> a = new LinkedHashMap<>();
        a.put("contributorId", c.toString());
        a.put("visionCutopenWatermelon", 0.12);
        MockMultipartHttpServletRequestBuilder b = multipart(SampleApiTest.BASE + "/" + id + "/parts");
        b.part(meta(a));
        b.part(file("cutOpen", "c.jpg", "image/jpeg", bytes(100, 5)));
        mvc.perform(b.header("X-Attest-Bypass", "simulator")).andExpect(status().isOk());
        mvc.perform(get(ADMIN + "/" + id)).andExpect(status().isOk())
                .andExpect(jsonPath("$.visionWatermelon").value(0.87))
                .andExpect(jsonPath("$.visionCutopenWatermelon").value(0.12));

        // Out of range / not a number: 400 invalid_meta, nothing stored.
        for (Object bad : List.of(1.5, -0.1, "0.5", true)) {
            Map<String, Object> mb = metaMap(c, false);
            mb.put("visionWatermelon", bad);
            submit(meta(mb), file("appearance", "a.jpg", "image/jpeg", bytes(50, 6)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("invalid_meta"));
        }
        // Integers 0 and 1 are valid numbers in range.
        Map<String, Object> edge = metaMap(c, false);
        edge.put("visionWatermelon", 0);
        edge.put("visionCutopenWatermelon", 1);
        submit(meta(edge), file("appearance", "a.jpg", "image/jpeg", bytes(50, 7)))
                .andExpect(status().isCreated());
    }
}

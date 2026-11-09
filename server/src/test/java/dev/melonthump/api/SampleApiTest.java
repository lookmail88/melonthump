package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.MaterialStorage;
import dev.melonthump.contrib.SamplePart;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HexFormat;
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
import org.springframework.transaction.support.TransactionTemplate;

/**
 * S2 sample endpoints (simulator bypass on): submit complete and
 * incomplete, append / resubmit, ownership, status transitions, tag /
 * meta validation, size and type rejection, and withdrawal as true
 * deletion (rows and files gone, audit row kept).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-sample-api;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class SampleApiTest {

    static final String BASE = "/api/v1/contributions/samples";

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ContributionService contributions;

    @Autowired
    private MaterialStorage storage;

    @Autowired
    private TransactionTemplate tx;

    private final ObjectMapper json = new ObjectMapper();

    // ---- fixtures ------------------------------------------------------------

    private UUID contributor(boolean approve) {
        UUID id = UUID.randomUUID();
        contributions.submitApplication(id, "tester");
        if (approve) {
            contributions.approve(id, "owner");
        }
        return id;
    }

    private static byte[] bytes(int n, int seed) {
        byte[] b = new byte[n];
        for (int i = 0; i < n; i++) {
            b[i] = (byte) (i * 31 + seed);
        }
        return b;
    }

    static MockPart file(String name, String filename, String contentType, byte[] content) {
        MockPart p = new MockPart(name, filename, content);
        p.getHeaders().setContentType(MediaType.parseMediaType(contentType));
        return p;
    }

    static MockPart meta(Object value) throws Exception {
        MockPart p = new MockPart("meta", new ObjectMapper().writeValueAsBytes(value));
        p.getHeaders().setContentType(MediaType.APPLICATION_JSON);
        return p;
    }

    private static Map<String, Object> metaMap(UUID contributorId) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", contributorId.toString());
        m.put("variety", "SEEDLESS");
        return m;
    }

    private static Map<String, Object> feedback(int score, List<String> tags, String band) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("score", score);
        f.put("tasteTags", tags);
        f.put("bandTruth", band);
        return f;
    }

    private ResultActions send(MockMultipartHttpServletRequestBuilder b, MockPart... parts) throws Exception {
        for (MockPart p : parts) {
            b.part(p);
        }
        return mvc.perform(b.header("X-Attest-Bypass", "simulator"));
    }

    private ResultActions submit(MockPart... parts) throws Exception {
        return send(multipart(BASE), parts);
    }

    private ResultActions append(long sampleId, UUID contributorId, MockPart... parts) throws Exception {
        return send(multipart(BASE + "/" + sampleId + "/parts?contributorId=" + contributorId), parts);
    }

    private JsonNode body(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }

    private long submitIncomplete(UUID c) throws Exception {
        return body(submit(meta(metaMap(c)), file("appearance", "a.jpg", "image/jpeg", bytes(100, 1)))
                .andExpect(status().isCreated())).get("id").asLong();
    }

    private List<Path> storedFiles(long sampleId) {
        List<Path> out = new ArrayList<>();
        for (String rel : jdbc.queryForList("SELECT stored_path FROM sample_files WHERE sample_id = ?",
                String.class, sampleId)) {
            out.add(storage.resolve(rel));
        }
        return out;
    }

    private List<Map<String, Object>> audit(long sampleId) {
        return jdbc.queryForList("SELECT actor, action, before_json, after_json FROM audit_log "
                + "WHERE object_type = 'SAMPLE' AND object_id = ? ORDER BY id", Long.toString(sampleId));
    }

    private void setStatus(long sampleId, String status, String reason) {
        jdbc.update("UPDATE samples SET status = ?, return_reason = ? WHERE id = ?", status, reason, sampleId);
    }

    private int sampleCount(UUID c) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM samples WHERE contributor_id = ?", Integer.class, c);
    }

    // ---- submit ----------------------------------------------------------------

    @Test
    void submitCompleteSampleStoresFilesAndAudits() throws Exception {
        UUID c = contributor(true);
        Map<String, Object> m = metaMap(c);
        m.put("weightGrams", 5400);
        m.put("weightProvenance", "SCALE_MEASURED");
        m.put("source", " farmers market ");
        m.put("melonDate", "2026-11-07");
        m.put("feedback", feedback(87, List.of("CRISP", "SWEET", "CRISP"), "RIPE"));
        byte[] photo1 = bytes(1000, 1);
        byte[] photo2 = bytes(1200, 2);
        byte[] audio = bytes(5000, 3);
        byte[] cut = bytes(800, 4);
        JsonNode s = body(submit(meta(m),
                file("appearance", "a1.jpg", "image/jpeg", photo1),
                file("appearance", "a2.heic", "image/heic", photo2),
                file("recording", "r.m4a", "audio/mp4", audio),
                file("cutOpen", "c.png", "image/png", cut))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("SUBMITTED"))
                .andExpect(jsonPath("$.complete").value(true))
                .andExpect(jsonPath("$.completeness.appearance").value(true))
                .andExpect(jsonPath("$.completeness.recording").value(true))
                .andExpect(jsonPath("$.completeness.cutOpen").value(true))
                .andExpect(jsonPath("$.completeness.feedback").value(true))
                .andExpect(jsonPath("$.source").value("farmers market"))
                .andExpect(jsonPath("$.feedback.score").value(87))
                .andExpect(jsonPath("$.feedback.tasteTags.length()").value(2))
                .andExpect(jsonPath("$.files.length()").value(4))
                .andExpect(jsonPath("$.files[0].storedPath").doesNotExist()));
        long id = s.get("id").asLong();

        // Layout <contributorId>/<sampleId>/<part>-<n>.<ext>; content and sha256 match.
        List<String> paths = jdbc.queryForList(
                "SELECT stored_path FROM sample_files WHERE sample_id = ? ORDER BY id", String.class, id);
        assertEquals(List.of(c + "/" + id + "/appearance-1.jpg", c + "/" + id + "/appearance-2.heic",
                c + "/" + id + "/recording-1.m4a", c + "/" + id + "/cut_open-1.png"), paths);
        byte[][] expected = {photo1, photo2, audio, cut};
        for (int i = 0; i < 4; i++) {
            Path p = storage.resolve(paths.get(i));
            assertTrue(java.util.Arrays.equals(expected[i], Files.readAllBytes(p)));
            assertEquals(HexFormat.of().formatHex(ContributionAttestGate.sha256(expected[i])),
                    s.get("files").get(i).get("sha256").asText());
            assertEquals(expected[i].length, s.get("files").get(i).get("sizeBytes").asLong());
        }
        assertEquals(Boolean.TRUE, jdbc.queryForObject("SELECT complete FROM samples WHERE id = ?", Boolean.class, id));

        List<Map<String, Object>> rows = audit(id);
        assertEquals(1, rows.size());
        assertEquals(c.toString(), rows.get(0).get("actor"));
        assertEquals("SAMPLE_SUBMITTED", rows.get(0).get("action"));
        assertNull(rows.get(0).get("before_json"));
        assertTrue(((String) rows.get(0).get("after_json")).contains("\"complete\":true"));
    }

    @Test
    void submitIncompleteSampleTracksWhatArrived() throws Exception {
        UUID c = contributor(true);
        submit(meta(metaMap(c)), file("recording", "r.wav", "audio/wav", bytes(300, 9)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.complete").value(false))
                .andExpect(jsonPath("$.completeness.appearance").value(false))
                .andExpect(jsonPath("$.completeness.recording").value(true))
                .andExpect(jsonPath("$.completeness.cutOpen").value(false))
                .andExpect(jsonPath("$.completeness.feedback").value(false))
                .andExpect(jsonPath("$.feedback").isEmpty());
        // Meta only (no files) is a valid, empty incomplete sample.
        submit(meta(metaMap(c))).andExpect(status().isCreated()).andExpect(jsonPath("$.files.length()").value(0));
        assertEquals(2, sampleCount(c));
    }

    @Test
    void submitRequiresApprovedKnownContributor() throws Exception {
        UUID pending = contributor(false);
        submit(meta(metaMap(pending))).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("contributor_not_approved"));
        submit(meta(metaMap(UUID.randomUUID()))).andExpect(status().isNotFound());
        UUID revoked = contributor(true);
        contributions.revoke(revoked, "owner");
        submit(meta(metaMap(revoked))).andExpect(status().isForbidden());
        assertEquals(0, sampleCount(pending) + sampleCount(revoked));
    }

    @Test
    void invalidMetaIs400() throws Exception {
        UUID c = contributor(true);
        submit(file("appearance", "a.jpg", "image/jpeg", bytes(10, 1))).andExpect(status().isBadRequest());
        Map<String, Object> m = metaMap(c);
        m.put("variety", "WATERMELON");
        submit(meta(m)).andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").value("invalid_meta"));
        m = metaMap(c);
        m.remove("variety");
        submit(meta(m)).andExpect(status().isBadRequest());
        m = metaMap(c);
        m.put("contributorId", "nope");
        submit(meta(m)).andExpect(status().isBadRequest());
        m = metaMap(c);
        m.put("weightGrams", -5);
        submit(meta(m)).andExpect(status().isBadRequest());
        m = metaMap(c);
        m.put("weightProvenance", "GUESS");
        submit(meta(m)).andExpect(status().isBadRequest());
        m = metaMap(c);
        m.put("melonDate", "07/11/2026");
        submit(meta(m)).andExpect(status().isBadRequest());
        m = metaMap(c);
        m.put("source", "x".repeat(65));
        submit(meta(m)).andExpect(status().isBadRequest());
        MockPart broken = new MockPart("meta", "{not json".getBytes(StandardCharsets.UTF_8));
        submit(broken).andExpect(status().isBadRequest());
        submit(meta(metaMap(c)), file("other", "x.jpg", "image/jpeg", bytes(10, 1)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").value("invalid_part"));
        submit(meta(metaMap(c)), file("recording", "r1.wav", "audio/wav", bytes(10, 1)),
                file("recording", "r2.wav", "audio/wav", bytes(10, 2))).andExpect(status().isBadRequest());
        assertEquals(0, sampleCount(c));
    }

    @Test
    void feedbackAndTasteTagValidation() throws Exception {
        UUID c = contributor(true);
        Map<String, Object> m = metaMap(c);
        m.put("feedback", feedback(50, List.of("CRISP", "CRUNCHY"), "RIPE"));
        submit(meta(m)).andExpect(status().isBadRequest()).andExpect(jsonPath("$.detail")
                .value(org.hamcrest.Matchers.containsString("CRUNCHY")));
        m.put("feedback", feedback(50, List.of("crisp"), "RIPE"));
        submit(meta(m)).andExpect(status().isBadRequest());
        m.put("feedback", feedback(101, List.of(), "RIPE"));
        submit(meta(m)).andExpect(status().isBadRequest());
        m.put("feedback", feedback(-1, List.of(), "RIPE"));
        submit(meta(m)).andExpect(status().isBadRequest());
        m.put("feedback", feedback(50, List.of(), null));
        submit(meta(m)).andExpect(status().isBadRequest());
        m.put("feedback", feedback(50, List.of(), "MUSHY"));
        submit(meta(m)).andExpect(status().isBadRequest());
        assertEquals(0, sampleCount(c));

        for (String tag : List.of("CRISP", "MEALY", "SANDY", "JUICY", "SWEET", "BLAND")) {
            m.put("feedback", feedback(0, List.of(tag), "UNRIPE"));
            submit(meta(m)).andExpect(status().isCreated()).andExpect(jsonPath("$.completeness.feedback").value(true));
        }
    }

    @Test
    void oversizeIs413AndWrongTypeIs400AndNothingIsStored() throws Exception {
        UUID c = contributor(true);
        submit(meta(metaMap(c)), file("appearance", "a.jpg", "image/jpeg", new byte[10 * 1024 * 1024 + 1]))
                .andExpect(status().isPayloadTooLarge()).andExpect(jsonPath("$.error").value("file_too_large"));
        submit(meta(metaMap(c)), file("cutOpen", "c.jpg", "image/jpeg", new byte[10 * 1024 * 1024 + 1]))
                .andExpect(status().isPayloadTooLarge());
        submit(meta(metaMap(c)), file("recording", "r.wav", "audio/wav", new byte[25 * 1024 * 1024 + 1]))
                .andExpect(status().isPayloadTooLarge());
        // Exactly at the limits is accepted.
        submit(meta(metaMap(c)), file("appearance", "a.jpg", "image/jpeg", new byte[10 * 1024 * 1024]),
                file("recording", "r.wav", "audio/wav", new byte[25 * 1024 * 1024]))
                .andExpect(status().isCreated());
        assertEquals(1, sampleCount(c));

        submit(meta(metaMap(c)), file("appearance", "a.txt", "text/plain", bytes(10, 1)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").value("unsupported_content_type"));
        submit(meta(metaMap(c)), file("recording", "r.jpg", "image/jpeg", bytes(10, 1)))
                .andExpect(status().isBadRequest());
        submit(meta(metaMap(c)), file("cutOpen", "c.wav", "audio/wav", bytes(10, 1)))
                .andExpect(status().isBadRequest());
        submit(meta(metaMap(c)), file("appearance", "a.bin", "application/octet-stream", bytes(10, 1)))
                .andExpect(status().isBadRequest());
        submit(meta(metaMap(c)), file("appearance", "a.jpg", "image/jpeg", new byte[0]))
                .andExpect(status().isBadRequest());
        assertEquals(1, sampleCount(c));
    }

    @Test
    void appearancePhotoCapIsEnforced() throws Exception {
        UUID c = contributor(true);
        MockPart[] parts = new MockPart[14];
        parts[0] = meta(metaMap(c));
        for (int i = 1; i < 14; i++) {
            parts[i] = file("appearance", "a" + i + ".jpg", "image/jpeg", bytes(10, i));
        }
        submit(parts).andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").value("invalid_sample"));
        assertEquals(0, sampleCount(c));
    }

    // ---- append ----------------------------------------------------------------

    @Test
    void appendCompletesSampleAndReplacesSingleFileParts() throws Exception {
        UUID c = contributor(true);
        long id = submitIncomplete(c);
        append(id, c, file("recording", "r.wav", "audio/wav", bytes(400, 5)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SUBMITTED"))
                .andExpect(jsonPath("$.completeness.recording").value(true))
                .andExpect(jsonPath("$.complete").value(false));
        Path firstRecording = storage.resolve(c + "/" + id + "/recording-1.wav");
        assertTrue(Files.exists(firstRecording));

        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", c.toString());
        m.put("feedback", feedback(72, List.of("JUICY"), "OVERRIPE"));
        append(id, c, meta(m), file("cutOpen", "c.jpg", "image/jpeg", bytes(50, 6)),
                file("recording", "r2.m4a", "audio/x-m4a", bytes(450, 7)),
                file("appearance", "a2.jpg", "image/jpeg", bytes(60, 8)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.complete").value(true))
                .andExpect(jsonPath("$.feedback.bandTruth").value("OVERRIPE"))
                .andExpect(jsonPath("$.files.length()").value(4));
        // Old recording replaced: row and file gone; one recording remains.
        assertFalse(Files.exists(firstRecording));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM sample_files WHERE sample_id = ? AND part = ?",
                Integer.class, id, SamplePart.RECORDING.name()));
        storedFiles(id).forEach(p -> assertTrue(Files.exists(p), p.toString()));

        List<Map<String, Object>> rows = audit(id);
        assertEquals(List.of("SAMPLE_SUBMITTED", "SAMPLE_APPENDED", "SAMPLE_APPENDED"),
                rows.stream().map(r -> r.get("action")).toList());
        rows.forEach(r -> assertEquals(c.toString(), r.get("actor")));
        assertTrue(((String) rows.get(2).get("before_json")).contains("\"complete\":false"));
        assertTrue(((String) rows.get(2).get("after_json")).contains("\"complete\":true"));

        // contributorId may come in the meta part instead of the query.
        Map<String, Object> only = new LinkedHashMap<>();
        only.put("contributorId", c.toString());
        send(multipart(BASE + "/" + id + "/parts"), meta(only), file("appearance", "a3.jpg", "image/jpeg", bytes(5, 1)))
                .andExpect(status().isOk());
        // Nothing to append.
        append(id, c).andExpect(status().isBadRequest());
        // Mismatching ids.
        Map<String, Object> other = new LinkedHashMap<>();
        other.put("contributorId", UUID.randomUUID().toString());
        append(id, c, meta(other), file("appearance", "a4.jpg", "image/jpeg", bytes(5, 1)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void appendToReturnedSampleResubmits() throws Exception {
        UUID c = contributor(true);
        long id = submitIncomplete(c);
        setStatus(id, "RETURNED", "cut-open photo missing");
        mvc.perform(get(BASE + "/" + id + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(jsonPath("$.status").value("RETURNED"))
                .andExpect(jsonPath("$.returnReason").value("cut-open photo missing"));
        append(id, c, file("cutOpen", "c.jpg", "image/jpeg", bytes(50, 6)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SUBMITTED"))
                .andExpect(jsonPath("$.returnReason").isEmpty());
        assertNull(jdbc.queryForObject("SELECT return_reason FROM samples WHERE id = ?", String.class, id));
        List<Map<String, Object>> rows = audit(id);
        assertEquals("SAMPLE_RESUBMITTED", rows.get(rows.size() - 1).get("action"));
        assertTrue(((String) rows.get(rows.size() - 1).get("before_json")).contains("\"status\":\"RETURNED\""));
    }

    @Test
    void appendIsRefusedInTerminalStatesForOthersAndForNonApproved() throws Exception {
        UUID c = contributor(true);
        long id = submitIncomplete(c);
        MockPart photo = file("appearance", "a.jpg", "image/jpeg", bytes(5, 1));

        UUID stranger = contributor(true);
        append(id, stranger, photo).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("sample_forbidden"));
        append(999_999, c, photo).andExpect(status().isForbidden());
        append(id, UUID.randomUUID(), photo).andExpect(status().isNotFound());

        setStatus(id, "APPROVED", null);
        append(id, c, photo).andExpect(status().isConflict());
        setStatus(id, "VOIDED", null);
        append(id, c, photo).andExpect(status().isConflict());

        setStatus(id, "SUBMITTED", null);
        contributions.revoke(c, "owner");
        append(id, c, photo).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("contributor_not_approved"));
        assertEquals(1, storedFiles(id).size());
        assertEquals(1, audit(id).size());
    }

    // ---- queries ---------------------------------------------------------------

    @Test
    void listAndDetailShowOnlyOwnSamplesWithoutPaths() throws Exception {
        UUID c = contributor(true);
        long first = submitIncomplete(c);
        long second = submitIncomplete(c);
        UUID other = contributor(true);
        long foreign = submitIncomplete(other);

        mvc.perform(get(BASE + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].id").value(second))
                .andExpect(jsonPath("$[1].id").value(first))
                .andExpect(jsonPath("$[0].variety").value("SEEDLESS"))
                .andExpect(jsonPath("$[0].completeness.appearance").value(true))
                .andExpect(jsonPath("$[0].complete").value(false))
                .andExpect(jsonPath("$[0].createdAt").isString())
                .andExpect(jsonPath("$[0].updatedAt").isString());

        String detail = mvc.perform(get(BASE + "/" + first + "?contributorId=" + c)
                        .header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.files.length()").value(1))
                .andExpect(jsonPath("$.files[0].part").value("APPEARANCE"))
                .andExpect(jsonPath("$.files[0].contentType").value("image/jpeg"))
                .andExpect(jsonPath("$.files[0].sizeBytes").value(100))
                .andReturn().getResponse().getContentAsString();
        assertFalse(detail.contains(c + "/"), "no stored path leaks: " + detail);

        mvc.perform(get(BASE + "/" + foreign + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isForbidden());
        mvc.perform(get(BASE + "/987654?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isForbidden());
        mvc.perform(get(BASE + "?contributorId=" + UUID.randomUUID()).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isNotFound());
        mvc.perform(get(BASE + "?contributorId=bad").header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isBadRequest());
        mvc.perform(get(BASE + "/abc?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isBadRequest());
    }

    // ---- withdraw ------------------------------------------------------------

    @Test
    void withdrawDeletesRowsAndFilesAndKeepsAuditRow() throws Exception {
        UUID c = contributor(true);
        long id = body(submit(meta(metaMap(c)),
                file("appearance", "a.jpg", "image/jpeg", bytes(100, 1)),
                file("recording", "r.wav", "audio/wav", bytes(100, 2))).andExpect(status().isCreated()))
                .get("id").asLong();
        List<Path> files = storedFiles(id);
        assertEquals(2, files.size());
        Path dir = storage.sampleDir(c, id);
        assertTrue(Files.isDirectory(dir));

        UUID stranger = contributor(true);
        mvc.perform(delete(BASE + "/" + id + "?contributorId=" + stranger).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isForbidden());
        files.forEach(p -> assertTrue(Files.exists(p)));

        mvc.perform(delete(BASE + "/" + id + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isNoContent());
        files.forEach(p -> assertFalse(Files.exists(p), p + " still on disk"));
        assertFalse(Files.exists(dir));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM samples WHERE id = ?", Integer.class, id));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM sample_files WHERE sample_id = ?", Integer.class, id));
        List<Map<String, Object>> rows = audit(id);
        assertEquals(List.of("SAMPLE_SUBMITTED", "SAMPLE_WITHDRAWN"), rows.stream().map(r -> r.get("action")).toList());
        assertEquals(c.toString(), rows.get(1).get("actor"));
        assertNull(rows.get(1).get("after_json"));
        assertTrue(((String) rows.get(1).get("before_json")).contains("\"sha256\""));

        mvc.perform(get(BASE + "/" + id + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isForbidden());
        mvc.perform(delete(BASE + "/" + id + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isForbidden());
    }

    @Test
    void withdrawRules() throws Exception {
        UUID c = contributor(true);
        long approved = submitIncomplete(c);
        long voided = submitIncomplete(c);
        long returned = submitIncomplete(c);
        setStatus(approved, "APPROVED", null);
        setStatus(voided, "VOIDED", null);
        setStatus(returned, "RETURNED", "blurry");
        for (long id : new long[] {approved, voided}) {
            mvc.perform(delete(BASE + "/" + id + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                    .andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("illegal_sample_state"));
            assertEquals(1, storedFiles(id).size());
            assertTrue(Files.exists(storedFiles(id).get(0)));
        }
        // A revoked contributor can still withdraw a RETURNED sample.
        contributions.revoke(c, "owner");
        mvc.perform(delete(BASE + "/" + returned + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(status().isNoContent());
        mvc.perform(get(BASE + "?contributorId=" + c).header("X-Attest-Bypass", "simulator"))
                .andExpect(jsonPath("$.length()").value(2));
    }

    @Test
    void storedFilesAreRemovedWhenTheTransactionRollsBack() {
        UUID c = UUID.randomUUID();
        Path[] written = new Path[1];
        tx.executeWithoutResult(status -> {
            MaterialStorage.StoredFile f = storage.store(c, 424242L, SamplePart.APPEARANCE, "jpg",
                    new ByteArrayInputStream(bytes(10, 1)));
            written[0] = storage.resolve(f.relativePath());
            assertTrue(Files.exists(written[0]));
            status.setRollbackOnly();
        });
        assertFalse(Files.exists(written[0]));
    }

    // ---- attest gating (bypass header absent) ---------------------------------

    @Test
    void everyContributionEndpointRequiresAttestation() throws Exception {
        UUID c = contributor(true);
        long id = submitIncomplete(c);
        mvc.perform(multipart(BASE).part(meta(metaMap(c)))).andExpect(status().isUnauthorized());
        mvc.perform(multipart(BASE + "/" + id + "/parts?contributorId=" + c)
                .part(file("appearance", "a.jpg", "image/jpeg", bytes(5, 1)))).andExpect(status().isUnauthorized());
        mvc.perform(get(BASE + "?contributorId=" + c)).andExpect(status().isUnauthorized());
        mvc.perform(get(BASE + "/" + id + "?contributorId=" + c)).andExpect(status().isUnauthorized());
        mvc.perform(delete(BASE + "/" + id + "?contributorId=" + c)).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/v1/contributions/status?contributorId=" + c)).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/contributions/applications").contentType(MediaType.APPLICATION_JSON)
                .content("{\"contributorId\":\"" + UUID.randomUUID() + "\",\"note\":\"x\"}"))
                .andExpect(status().isUnauthorized());
        // A wrong bypass value is no bypass.
        mvc.perform(get(BASE + "?contributorId=" + c).header("X-Attest-Bypass", "device"))
                .andExpect(status().isUnauthorized());
        assertEquals(1, sampleCount(c));
        assertEquals(1, storedFiles(id).size());
    }
}

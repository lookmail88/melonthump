package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import org.springframework.test.web.servlet.ResultActions;

/**
 * Owner admin API: application listing with status filter, approve /
 * decline / revoke transitions, refused transitions, idempotent repeats,
 * and the audit rows each change writes (actor = owner).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-admin-api;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdminApiTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    private final ObjectMapper json = new ObjectMapper();

    private UUID applicant(String note) throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(post("/api/v1/contributions/applications").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("contributorId", id.toString(), "note", note))))
                .andExpect(status().isCreated());
        return id;
    }

    private ResultActions approve(UUID id) throws Exception {
        return mvc.perform(post("/api/admin/applications/" + id + "/approve"));
    }

    private ResultActions decline(UUID id) throws Exception {
        return mvc.perform(post("/api/admin/applications/" + id + "/decline"));
    }

    private ResultActions revoke(UUID id) throws Exception {
        return mvc.perform(post("/api/admin/contributors/" + id + "/revoke"));
    }

    private List<Map<String, Object>> audit(UUID id) {
        return jdbc.queryForList("SELECT actor, action, before_json, after_json FROM audit_log "
                + "WHERE object_type = 'CONTRIBUTOR' AND object_id = ? ORDER BY id", id.toString());
    }

    private String statusInDb(UUID id) {
        return jdbc.queryForObject("SELECT status FROM contributors WHERE contributor_id = ?", String.class, id);
    }

    private List<String> listedIds(String statusFilter) throws Exception {
        var request = get("/api/admin/applications");
        if (statusFilter != null) {
            request = request.param("status", statusFilter);
        }
        JsonNode arr = json.readTree(mvc.perform(request).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
        List<String> ids = new ArrayList<>();
        arr.forEach(n -> ids.add(n.get("contributorId").asText()));
        return ids;
    }

    @Test
    void approveWritesStatusAndOwnerAuditRow() throws Exception {
        UUID id = applicant("Jordan");
        approve(id).andExpect(status().isOk())
                .andExpect(jsonPath("$.contributorId").value(id.toString()))
                .andExpect(jsonPath("$.status").value("APPROVED"))
                .andExpect(jsonPath("$.note").value("Jordan"));
        assertEquals("APPROVED", statusInDb(id));

        List<Map<String, Object>> rows = audit(id);
        assertEquals(2, rows.size());
        assertEquals("APPLICATION_SUBMITTED", rows.get(0).get("action"));
        Map<String, Object> row = rows.get(1);
        assertEquals("owner", row.get("actor"));
        assertEquals("APPLICATION_APPROVED", row.get("action"));
        assertEquals("PENDING", json.readTree((String) row.get("before_json")).get("status").asText());
        assertEquals("APPROVED", json.readTree((String) row.get("after_json")).get("status").asText());

        mvc.perform(get("/api/v1/contributions/status").param("contributorId", id.toString()))
                .andExpect(jsonPath("$.status").value("APPROVED"));
    }

    @Test
    void declineWritesStatusAndAuditRow() throws Exception {
        UUID id = applicant("Riley");
        decline(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("DECLINED"));
        assertEquals("DECLINED", statusInDb(id));
        Map<String, Object> row = audit(id).get(1);
        assertEquals("owner", row.get("actor"));
        assertEquals("APPLICATION_DECLINED", row.get("action"));
    }

    @Test
    void revokeApprovedContributorAndReinstate() throws Exception {
        UUID id = applicant("Casey");
        approve(id).andExpect(status().isOk());
        revoke(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("REVOKED"));
        assertEquals("REVOKED", statusInDb(id));
        Map<String, Object> row = audit(id).get(2);
        assertEquals("owner", row.get("actor"));
        assertEquals("CONTRIBUTOR_REVOKED", row.get("action"));
        assertEquals("APPROVED", json.readTree((String) row.get("before_json")).get("status").asText());
        assertEquals("REVOKED", json.readTree((String) row.get("after_json")).get("status").asText());

        // Switching a revoked contributor back on is an approve.
        approve(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("APPROVED"));
        assertEquals(4, audit(id).size());
    }

    @Test
    void refusedTransitionsAre409AndWriteNothing() throws Exception {
        UUID pending = applicant("P");
        revoke(pending).andExpect(status().isConflict());
        assertEquals("PENDING", statusInDb(pending));

        UUID approved = applicant("A");
        approve(approved).andExpect(status().isOk());
        decline(approved).andExpect(status().isConflict());
        assertEquals("APPROVED", statusInDb(approved));

        UUID declined = applicant("D");
        decline(declined).andExpect(status().isOk());
        revoke(declined).andExpect(status().isConflict());

        assertEquals(1, audit(pending).size());
        assertEquals(2, audit(approved).size());
        assertEquals(2, audit(declined).size());
    }

    @Test
    void repeatingAnActionIsIdempotentWithoutNewAuditRows() throws Exception {
        UUID id = applicant("Repeat");
        approve(id).andExpect(status().isOk());
        approve(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("APPROVED"));
        revoke(id).andExpect(status().isOk());
        revoke(id).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("REVOKED"));
        assertEquals(3, audit(id).size());

        UUID d = applicant("Decline twice");
        decline(d).andExpect(status().isOk());
        decline(d).andExpect(status().isOk());
        assertEquals(2, audit(d).size());
    }

    @Test
    void unknownContributorIs404() throws Exception {
        UUID unknown = UUID.randomUUID();
        approve(unknown).andExpect(status().isNotFound());
        decline(unknown).andExpect(status().isNotFound());
        revoke(unknown).andExpect(status().isNotFound());
        assertNull(jdbc.queryForObject("SELECT MAX(id) FROM audit_log WHERE object_id = ?", Long.class,
                unknown.toString()));
    }

    @Test
    void malformedIdIs400() throws Exception {
        mvc.perform(post("/api/admin/applications/not-a-uuid/approve")).andExpect(status().isBadRequest());
    }

    @Test
    void listFiltersByStatus() throws Exception {
        UUID pending = applicant("list-pending");
        UUID approved = applicant("list-approved");
        UUID declined = applicant("list-declined");
        approve(approved).andExpect(status().isOk());
        decline(declined).andExpect(status().isOk());

        List<String> all = listedIds(null);
        assertEquals(true, all.containsAll(List.of(pending.toString(), approved.toString(), declined.toString())));

        List<String> onlyPending = listedIds("PENDING");
        assertEquals(true, onlyPending.contains(pending.toString()));
        assertEquals(false, onlyPending.contains(approved.toString()));
        assertEquals(false, onlyPending.contains(declined.toString()));

        List<String> onlyApproved = listedIds("approved");
        assertEquals(true, onlyApproved.contains(approved.toString()));
        assertEquals(false, onlyApproved.contains(pending.toString()));

        mvc.perform(get("/api/admin/applications").param("status", "BOGUS")).andExpect(status().isBadRequest());

        mvc.perform(get("/api/admin/applications").param("status", "PENDING"))
                .andExpect(jsonPath("$[?(@.contributorId == '" + pending + "')].note").value("list-pending"));
    }
}

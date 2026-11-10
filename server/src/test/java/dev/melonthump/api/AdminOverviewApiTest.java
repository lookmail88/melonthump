package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.IncentiveService;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/** S4 overview (page D) counts on a seeded scenario in a database of its own. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-s4-overview;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdminOverviewApiTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ContributionService contributions;

    @Autowired
    private IncentiveService incentives;

    private void approve(long id) throws Exception {
        mvc.perform(post("/api/admin/samples/" + id + "/approve")).andExpect(status().isOk());
    }

    @Test
    void countsMatchTheSeededScenario() throws Exception {
        JsonNode empty = S4Fixtures.body(mvc.perform(get("/api/admin/overview")).andExpect(status().isOk()));
        assertEquals(0, empty.get("completeSamplesApproved").asLong());
        assertEquals(0, empty.get("pendingReview").asLong());
        assertEquals(0, empty.get("adFreeOutstanding").asLong());
        assertEquals(0, empty.get("contributors").get("PENDING").asLong());
        assertEquals(0, empty.get("samples").get("VOIDED").asLong());

        S4Fixtures fx = new S4Fixtures(mvc, contributions);
        // Contributors: 2 PENDING, 2 APPROVED (a, b), 1 DECLINED, 1 REVOKED.
        fx.pendingContributor();
        fx.pendingContributor();
        UUID a = fx.approvedContributor();
        UUID b = fx.approvedContributor();
        contributions.decline(fx.pendingContributor(), "owner");
        contributions.revoke(fx.approvedContributor(), "owner");

        // Samples: 3 complete approved (one later voided), 1 incomplete approved,
        // 1 returned, 2 still submitted.
        long a1 = fx.completeSample(a);
        long a2 = fx.completeSample(a);
        long b1 = fx.completeSample(b);
        long b2 = fx.incompleteSample(b);
        long b3 = fx.incompleteSample(b);
        fx.completeSample(a);
        fx.incompleteSample(b);
        approve(a1);
        approve(a2);
        approve(b1);
        approve(b2);
        mvc.perform(post("/api/admin/samples/" + b3 + "/return").contentType(MediaType.APPLICATION_JSON)
                .content("{\"reason\":\"add the cut-open photo\"}")).andExpect(status().isOk());
        // Void b1: clawback of its 5 units (b's balance 5 -> 0).
        mvc.perform(post("/api/admin/samples/" + b1 + "/void")).andExpect(status().isOk());
        // Balances: a = 10 earned + 4 granted - 1 spent = 13; b = 0 + 2 granted = 2.
        incentives.grant(a, 4, "bonus", "owner");
        incentives.spend(a);
        incentives.grant(b, 2, "bonus", "owner");

        JsonNode o = S4Fixtures.body(mvc.perform(get("/api/admin/overview")).andExpect(status().isOk()));
        assertEquals(List.of("contributors", "samples", "completeSamplesApproved", "pendingReview",
                "adFreeOutstanding"), names(o));
        assertEquals(List.of("PENDING", "APPROVED", "DECLINED", "REVOKED"), names(o.get("contributors")));
        assertEquals(2, o.get("contributors").get("PENDING").asLong());
        assertEquals(2, o.get("contributors").get("APPROVED").asLong());
        assertEquals(1, o.get("contributors").get("DECLINED").asLong());
        assertEquals(1, o.get("contributors").get("REVOKED").asLong());
        assertEquals(List.of("SUBMITTED", "APPROVED", "RETURNED", "VOIDED"), names(o.get("samples")));
        assertEquals(2, o.get("samples").get("SUBMITTED").asLong());
        assertEquals(3, o.get("samples").get("APPROVED").asLong());
        assertEquals(1, o.get("samples").get("RETURNED").asLong());
        assertEquals(1, o.get("samples").get("VOIDED").asLong());
        assertEquals(2, o.get("completeSamplesApproved").asLong(), "a1 + a2; b2 incomplete, b1 voided");
        assertEquals(2, o.get("pendingReview").asLong());
        assertEquals(15, o.get("adFreeOutstanding").asLong());
    }

    private static List<String> names(JsonNode n) {
        List<String> out = new java.util.ArrayList<>();
        n.fieldNames().forEachRemaining(out::add);
        return out;
    }
}

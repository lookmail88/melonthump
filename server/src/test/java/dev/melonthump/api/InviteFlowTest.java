package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.store.InviteStore;
import java.util.UUID;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/**
 * Invite flow over the dev simulator bypass (the attestation gate itself
 * is covered in InviteAttestTest): code issue, attribution,
 * confirm-on-first-thump, double-count prevention, the cap, and
 * once-only, idempotent reward claims.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-invite;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class InviteFlowTest {

    @Autowired
    private MockMvc mvc;

    private final ObjectMapper json = new ObjectMapper();

    private ResultActions call(String path, String body) throws Exception {
        return mvc.perform(post("/api/v1/invite/" + path)
                .header("X-Attest-Bypass", "simulator")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private static String install(UUID id) {
        return "{\"installId\":\"" + id + "\"}";
    }

    private String codeOf(UUID inviter) throws Exception {
        String body = call("code", install(inviter)).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return json.readTree(body).get("code").asText();
    }

    private ResultActions attribute(UUID invitee, String code, String source) throws Exception {
        return call("attribute", "{\"installId\":\"" + invitee + "\",\"code\":\"" + code
                + "\",\"source\":\"" + source + "\"}");
    }

    private JsonNode confirm(UUID invitee) throws Exception {
        return json.readTree(call("confirm", install(invitee)).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
    }

    private JsonNode claim(UUID installId, UUID claimId) throws Exception {
        return json.readTree(call("claim", "{\"installId\":\"" + installId + "\",\"claimId\":\"" + claimId + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
    }

    private JsonNode standing(UUID installId) throws Exception {
        return json.readTree(call("status", install(installId)).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
    }

    @Test
    void requiresAttestation() throws Exception {
        mvc.perform(post("/api/v1/invite/code").contentType(MediaType.APPLICATION_JSON)
                        .content(install(UUID.randomUUID())))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/invite/claim").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"installId\":\"" + UUID.randomUUID() + "\",\"claimId\":\"" + UUID.randomUUID() + "\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void codeIsStablePerInstallAndWellFormed() throws Exception {
        UUID inviter = UUID.randomUUID();
        String code = codeOf(inviter);
        assertEquals(code, codeOf(inviter));
        assertEquals(code, InviteStore.normalizeCode(code));
        assertNotEquals(code, codeOf(UUID.randomUUID()));
        assertEquals(code, InviteStore.normalizeCode(code.substring(0, 4).toLowerCase() + "-" + code.substring(4)));
    }

    @Test
    void fullFlowConfirmsOnFirstThumpAndRewardsBothSidesOnce() throws Exception {
        UUID inviter = UUID.randomUUID();
        UUID invitee = UUID.randomUUID();
        String code = codeOf(inviter);

        attribute(invitee, code, "link").andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("attributed"));
        // Attribution alone is not a confirmation: nothing to claim yet.
        assertEquals(0, standing(inviter).get("confirmedInvites").asInt());
        assertEquals(0, claim(inviter, UUID.randomUUID()).get("credits").asInt());
        assertEquals(0, claim(invitee, UUID.randomUUID()).get("credits").asInt());

        // Invitee completes the first thump analysis -> confirmation.
        JsonNode confirmed = confirm(invitee);
        assertEquals("confirmed", confirmed.get("status").asText());
        assertTrue(confirmed.get("rewarded").asBoolean());
        // Re-confirming never counts twice.
        assertEquals("already_confirmed", confirm(invitee).get("status").asText());

        JsonNode inviterStatus = standing(inviter);
        assertEquals(1, inviterStatus.get("confirmedInvites").asInt());
        assertEquals(5, inviterStatus.get("inviterCreditsClaimable").asInt());
        assertEquals(10, inviterStatus.get("cap").asInt());
        JsonNode inviteeStatus = standing(invitee);
        assertTrue(inviteeStatus.get("invited").asBoolean());
        assertTrue(inviteeStatus.get("inviteeConfirmed").asBoolean());
        assertEquals(5, inviteeStatus.get("inviteeCreditsClaimable").asInt());

        // +5 / +5, each claimable exactly once; a retry with the same
        // claimId is idempotent (same answer), a new claimId gets nothing.
        UUID inviterClaim = UUID.randomUUID();
        assertEquals(5, claim(inviter, inviterClaim).get("credits").asInt());
        assertEquals(5, claim(inviter, inviterClaim).get("credits").asInt());
        assertEquals(0, claim(inviter, UUID.randomUUID()).get("credits").asInt());
        UUID inviteeClaim = UUID.randomUUID();
        JsonNode inviteeClaimed = claim(invitee, inviteeClaim);
        assertEquals(5, inviteeClaimed.get("credits").asInt());
        assertTrue(inviteeClaimed.get("inviteeReward").asBoolean());
        assertEquals(0, claim(invitee, UUID.randomUUID()).get("credits").asInt());
        assertEquals(0, standing(inviter).get("inviterCreditsClaimable").asInt());
        assertEquals(0, standing(invitee).get("inviteeCreditsClaimable").asInt());
    }

    @Test
    void sameInstallIsNeverCountedTwice() throws Exception {
        UUID inviterA = UUID.randomUUID();
        UUID inviterB = UUID.randomUUID();
        UUID invitee = UUID.randomUUID();
        String codeA = codeOf(inviterA);
        String codeB = codeOf(inviterB);

        attribute(invitee, codeA, "code").andExpect(status().isOk());
        // Same code again (link re-opened): idempotent, still one row.
        attribute(invitee, codeA, "link").andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("already_attributed"));
        // A second inviter can never claim the same install.
        attribute(invitee, codeB, "code").andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value("already_invited"));

        confirm(invitee);
        confirm(invitee);
        assertEquals(1, standing(inviterA).get("confirmedInvites").asInt());
        assertEquals(0, standing(inviterB).get("confirmedInvites").asInt());
    }

    @Test
    void refusesSelfInviteUnknownAndMalformedCodes() throws Exception {
        UUID inviter = UUID.randomUUID();
        String code = codeOf(inviter);
        attribute(inviter, code, "code").andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value("self_invite"));
        attribute(UUID.randomUUID(), "ZZZZZZZZ", "code").andExpect(status().isNotFound());
        attribute(UUID.randomUUID(), "not a code!", "code").andExpect(status().isBadRequest());
        attribute(UUID.randomUUID(), code, "carrier_pigeon").andExpect(status().isBadRequest());
        // Confirm without attribution: nothing happens.
        assertEquals("not_invited", confirm(UUID.randomUUID()).get("status").asText());
    }

    @Test
    void installThatAlreadyThumpedCannotBeAttributed() throws Exception {
        UUID existingUser = UUID.randomUUID();
        // The 1.1.0 stats ledger already holds a real analysis for it.
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"installId\":\"" + existingUser + "\",\"events\":[{\"eventId\":\""
                                + UUID.randomUUID() + "\",\"type\":\"analysis_completed\","
                                + "\"clientTs\":1790000000123,\"verdict\":\"RIPE\"}]}"))
                .andExpect(status().isAccepted());
        attribute(existingUser, codeOf(UUID.randomUUID()), "code")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value("already_active"));
    }

    @Test
    void capRewardsAtMostTenInvitesPerInviter() throws Exception {
        UUID inviter = UUID.randomUUID();
        String code = codeOf(inviter);
        UUID eleventh = null;
        for (int i = 0; i < 11; i++) {
            UUID invitee = UUID.randomUUID();
            attribute(invitee, code, "code").andExpect(status().isOk());
            JsonNode c = confirm(invitee);
            assertEquals(i < 10, c.get("rewarded").asBoolean(), "invite #" + (i + 1));
            eleventh = invitee;
        }
        JsonNode s = standing(inviter);
        assertEquals(11, s.get("confirmedInvites").asInt());
        assertEquals(10, s.get("rewardedInvites").asInt());
        assertEquals(50, claim(inviter, UUID.randomUUID()).get("credits").asInt());
        // Past the cap: no reward for either side.
        assertEquals(0, standing(eleventh).get("inviteeCreditsClaimable").asInt());
        assertEquals(0, claim(eleventh, UUID.randomUUID()).get("credits").asInt());
    }

    @Test
    void landingPageShowsCodeAndAppLink() throws Exception {
        String code = codeOf(UUID.randomUUID());
        mvc.perform(get("/invite/" + code.toLowerCase()))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(Matchers.containsString(code)))
                .andExpect(content().string(Matchers.containsString("melonthump://invite?code=" + code)));
        mvc.perform(get("/invite/ZZZZZZZZ")).andExpect(status().isNotFound());
        mvc.perform(get("/invite/%3Cscript%3E")).andExpect(status().isNotFound());
    }
}

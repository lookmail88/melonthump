package dev.melonthump.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.SyntheticAttest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;

/**
 * Invite endpoints behind real (synthetic-chain) App Attest assertions:
 * the body's installId is bound to the attested key's install, and one
 * App Attest key can be attributed as an invitee only once.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:melonthump-invite-attest;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        // Prove the real gate: no simulator bypass on this backend.
        "melonthump.attest.debug-bypass-enabled=false"
})
class InviteAttestTest {

    @DynamicPropertySource
    static void attestRoot(DynamicPropertyRegistry registry) {
        registry.add("melonthump.attest.root-ca-location", SyntheticAttest::rootCaLocation);
    }

    @Autowired
    private MockMvc mvc;

    private final ObjectMapper json = new ObjectMapper();
    private final AtomicLong counter = new AtomicLong();

    private String fetchChallenge() throws Exception {
        MvcResult result = mvc.perform(post("/api/v1/attest/challenge")).andExpect(status().isOk()).andReturn();
        return json.readTree(result.getResponse().getContentAsString()).get("challenge").asText();
    }

    private void enroll(SyntheticAttest.Device device, UUID installId) throws Exception {
        String challengeB64 = fetchChallenge();
        byte[] attestation = SyntheticAttest.attestationObject(
                device, Base64.getDecoder().decode(challengeB64), "production");
        mvc.perform(post("/api/v1/attest/enroll").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"keyId\":\"" + device.keyId() + "\",\"attestationObject\":\""
                                + Base64.getEncoder().encodeToString(attestation) + "\",\"challenge\":\""
                                + challengeB64 + "\",\"installId\":\"" + installId + "\"}"))
                .andExpect(status().isCreated());
    }

    private ResultActions attested(SyntheticAttest.Device device, String path, String body) throws Exception {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        String challenge = fetchChallenge();
        byte[] assertion = SyntheticAttest.assertionObject(
                device, Base64.getDecoder().decode(challenge), bytes, counter.incrementAndGet());
        return mvc.perform(post("/api/v1/invite/" + path)
                .header("X-Key-Id", device.keyId())
                .header("X-Assertion", Base64.getEncoder().encodeToString(assertion))
                .header("X-Challenge", challenge)
                .contentType(MediaType.APPLICATION_JSON).content(bytes));
    }

    @Test
    void attestedFlowBindsInstallAndCountsAKeyOnce() throws Exception {
        SyntheticAttest.Device inviterDevice = SyntheticAttest.newDevice();
        UUID inviter = UUID.randomUUID();
        enroll(inviterDevice, inviter);
        String code = json.readTree(attested(inviterDevice, "code", "{\"installId\":\"" + inviter + "\"}")
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString()).get("code").asText();

        // Bypass header is refused on this backend.
        mvc.perform(post("/api/v1/invite/code").header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"installId\":\"" + inviter + "\"}"))
                .andExpect(status().isUnauthorized());

        SyntheticAttest.Device inviteeDevice = SyntheticAttest.newDevice();
        UUID invitee = UUID.randomUUID();
        enroll(inviteeDevice, invitee);

        // A key cannot act for another install.
        attested(inviteeDevice, "attribute",
                "{\"installId\":\"" + UUID.randomUUID() + "\",\"code\":\"" + code + "\",\"source\":\"code\"}")
                .andExpect(status().isUnauthorized());

        attested(inviteeDevice, "attribute",
                "{\"installId\":\"" + invitee + "\",\"code\":\"" + code + "\",\"source\":\"link\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("attributed"));

        // Same device key re-enrolled under a fresh install id (app data
        // wiped, key kept): still the same key, never counted twice.
        UUID secondInstall = UUID.randomUUID();
        enroll(inviteeDevice, secondInstall);
        attested(inviteeDevice, "attribute",
                "{\"installId\":\"" + secondInstall + "\",\"code\":\"" + code + "\",\"source\":\"code\"}")
                .andExpect(status().isConflict());
    }
}

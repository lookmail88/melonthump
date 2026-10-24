package dev.melonthump.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.SyntheticAttest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.UUID;
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

/**
 * End-to-end App Attest flow against a synthetic Apple chain: enroll,
 * attested upload, challenge replay, counter regression, idempotent
 * re-upload, and the attested-only version-policy field.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-flow;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AttestFlowTest {

    @DynamicPropertySource
    static void attestRoot(DynamicPropertyRegistry registry) {
        registry.add("melonthump.attest.root-ca-location", SyntheticAttest::rootCaLocation);
    }

    @Autowired
    private MockMvc mvc;

    private final ObjectMapper json = new ObjectMapper();

    private String fetchChallenge() throws Exception {
        MvcResult result = mvc.perform(post("/api/v1/attest/challenge"))
                .andExpect(status().isOk())
                .andReturn();
        return json.readTree(result.getResponse().getContentAsString()).get("challenge").asText();
    }

    private void enroll(SyntheticAttest.Device device, UUID installId, String environment) throws Exception {
        String challengeB64 = fetchChallenge();
        byte[] challenge = Base64.getDecoder().decode(challengeB64);
        byte[] attestation = SyntheticAttest.attestationObject(device, challenge, environment);
        String body = "{\"keyId\":\"" + device.keyId() + "\",\"attestationObject\":\""
                + Base64.getEncoder().encodeToString(attestation) + "\",\"challenge\":\""
                + challengeB64 + "\",\"installId\":\"" + installId + "\"}";
        mvc.perform(post("/api/v1/attest/enroll")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.environment").value(environment));
        // The enrollment challenge is single-use: replaying the enroll fails.
        mvc.perform(post("/api/v1/attest/enroll")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
    }

    private static String eventsBody(UUID installId) {
        return "{\"installId\":\"" + installId + "\",\"sessionId\":\"" + UUID.randomUUID() + "\",\"events\":["
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"analysis_completed\",\"clientTs\":1790000000123,\"verdict\":\"RIPE\"},"
                + "{\"eventId\":\"" + UUID.randomUUID() + "\",\"type\":\"ad_requested\",\"clientTs\":1790000000456,\"slot\":\"rewarded_main\",\"unitSource\":\"server\"}]}";
    }

    @Test
    void enrollUploadReplayAndCounterRegression() throws Exception {
        SyntheticAttest.Device device = SyntheticAttest.newDevice();
        UUID installId = UUID.randomUUID();
        enroll(device, installId, "production");

        String body = eventsBody(installId);
        byte[] bodyBytes = body.getBytes(StandardCharsets.UTF_8);

        // Happy path: counter 1 -> both events accepted.
        String challenge1 = fetchChallenge();
        byte[] assertion1 = SyntheticAttest.assertionObject(
                device, Base64.getDecoder().decode(challenge1), bodyBytes, 1);
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Key-Id", device.keyId())
                        .header("X-Assertion", Base64.getEncoder().encodeToString(assertion1))
                        .header("X-Challenge", challenge1)
                        .contentType(MediaType.APPLICATION_JSON).content(bodyBytes))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.accepted").value(2));

        // Replay of the very same assertion: challenge already consumed.
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Key-Id", device.keyId())
                        .header("X-Assertion", Base64.getEncoder().encodeToString(assertion1))
                        .header("X-Challenge", challenge1)
                        .contentType(MediaType.APPLICATION_JSON).content(bodyBytes))
                .andExpect(status().isUnauthorized());

        // Fresh challenge but the counter does not increase: rejected.
        String challenge2 = fetchChallenge();
        byte[] staleCounter = SyntheticAttest.assertionObject(
                device, Base64.getDecoder().decode(challenge2), bodyBytes, 1);
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Key-Id", device.keyId())
                        .header("X-Assertion", Base64.getEncoder().encodeToString(staleCounter))
                        .header("X-Challenge", challenge2)
                        .contentType(MediaType.APPLICATION_JSON).content(bodyBytes))
                .andExpect(status().isUnauthorized());

        // Counter advances; the same batch re-uploads idempotently (0 new).
        String challenge3 = fetchChallenge();
        byte[] assertion3 = SyntheticAttest.assertionObject(
                device, Base64.getDecoder().decode(challenge3), bodyBytes, 2);
        mvc.perform(post("/api/v1/stats/events")
                        .header("X-Key-Id", device.keyId())
                        .header("X-Assertion", Base64.getEncoder().encodeToString(assertion3))
                        .header("X-Challenge", challenge3)
                        .contentType(MediaType.APPLICATION_JSON).content(bodyBytes))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.accepted").value(0));
    }

    @Test
    void policyFieldAppearsOnlyWithValidAssertion() throws Exception {
        SyntheticAttest.Device device = SyntheticAttest.newDevice();
        enroll(device, UUID.randomUUID(), "production");

        // Legacy view: no headers -> field absent entirely.
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "1.0.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rewardedAdUnitId").doesNotExist());

        // Attested view: assertion over the canonical request string.
        String canonical = "GET /api/v1/version/getclientversion?currentVersion=1.0.0";
        String challenge = fetchChallenge();
        byte[] assertion = SyntheticAttest.assertionObject(device,
                Base64.getDecoder().decode(challenge),
                canonical.getBytes(StandardCharsets.UTF_8), 1);
        mvc.perform(get("/api/v1/version/getclientversion")
                        .param("currentVersion", "1.0.0")
                        .header("X-Key-Id", device.keyId())
                        .header("X-Assertion", Base64.getEncoder().encodeToString(assertion))
                        .header("X-Challenge", challenge))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rewardedAdUnitId").value("test-placeholder-unit-id"));
    }

    @Test
    void developEnvironmentEnrollsWhenBackendAcceptsIt() throws Exception {
        SyntheticAttest.Device device = SyntheticAttest.newDevice();
        enroll(device, UUID.randomUUID(), "develop");
    }
}

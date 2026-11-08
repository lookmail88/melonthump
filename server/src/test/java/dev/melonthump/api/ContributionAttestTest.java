package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.SyntheticAttest;
import dev.melonthump.contrib.ContributionService;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockPart;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.AbstractMockHttpServletRequestBuilder;

/**
 * Contribution endpoints behind real (synthetic-chain) App Attest
 * assertions with the simulator bypass switched off: what each kind of
 * request's assertion covers (JSON body, canonical request string,
 * canonical multipart string), and that the bypass header, missing
 * headers or an assertion over different bytes are refused with 401.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:melonthump-contrib-attest;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "melonthump.attest.debug-bypass-enabled=false"
})
class ContributionAttestTest {

    static final String BASE = "/api/v1/contributions/samples";

    @DynamicPropertySource
    static void attestRoot(DynamicPropertyRegistry registry) {
        registry.add("melonthump.attest.root-ca-location", SyntheticAttest::rootCaLocation);
    }

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ContributionService contributions;

    @Autowired
    private JdbcTemplate jdbc;

    private final ObjectMapper json = new ObjectMapper();
    private final AtomicLong counter = new AtomicLong();
    private SyntheticAttest.Device device;

    private String fetchChallenge() throws Exception {
        MvcResult result = mvc.perform(post("/api/v1/attest/challenge")).andExpect(status().isOk()).andReturn();
        return json.readTree(result.getResponse().getContentAsString()).get("challenge").asText();
    }

    @BeforeEach
    void enroll() throws Exception {
        device = SyntheticAttest.newDevice();
        String challengeB64 = fetchChallenge();
        byte[] attestation = SyntheticAttest.attestationObject(
                device, Base64.getDecoder().decode(challengeB64), "production");
        mvc.perform(post("/api/v1/attest/enroll").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"keyId\":\"" + device.keyId() + "\",\"attestationObject\":\""
                                + Base64.getEncoder().encodeToString(attestation) + "\",\"challenge\":\""
                                + challengeB64 + "\",\"installId\":\"" + UUID.randomUUID() + "\"}"))
                .andExpect(status().isCreated());
    }

    private <T extends AbstractMockHttpServletRequestBuilder<?>> T signed(T builder, byte[] covered) throws Exception {
        String challenge = fetchChallenge();
        byte[] assertion = SyntheticAttest.assertionObject(
                device, Base64.getDecoder().decode(challenge), covered, counter.incrementAndGet());
        builder.header("X-Key-Id", device.keyId())
                .header("X-Assertion", Base64.getEncoder().encodeToString(assertion))
                .header("X-Challenge", challenge);
        return builder;
    }

    private static byte[] utf8(String s) {
        return s.getBytes(StandardCharsets.UTF_8);
    }

    private static byte[] multipartCanonical(String path, MockPart... parts) throws Exception {
        List<ContributionAttestGate.PartDigest> digests = new ArrayList<>();
        for (MockPart p : parts) {
            digests.add(new ContributionAttestGate.PartDigest(p.getName(),
                    ContributionAttestGate.sha256(p.getInputStream().readAllBytes())));
        }
        return utf8(ContributionAttestGate.canonicalMultipartString("POST", path, digests));
    }

    @Test
    void applicationAndStatusCoverBodyAndCanonicalRequest() throws Exception {
        UUID c = UUID.randomUUID();
        byte[] body = utf8("{\"contributorId\":\"" + c + "\",\"note\":\"attested tester\"}");
        mvc.perform(post("/api/v1/contributions/applications").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/contributions/applications").header("X-Attest-Bypass", "simulator")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        // Assertion over different bytes is refused.
        mvc.perform(signed(post("/api/v1/contributions/applications"), utf8("{}"))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        mvc.perform(signed(post("/api/v1/contributions/applications"), body)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("PENDING"));

        String path = "/api/v1/contributions/status?contributorId=" + c;
        mvc.perform(get(path)).andExpect(status().isUnauthorized());
        mvc.perform(signed(get(path), utf8("GET /api/v1/contributions/status?contributorId=" + UUID.randomUUID())))
                .andExpect(status().isUnauthorized());
        mvc.perform(signed(get(path), utf8("GET " + path)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void sampleEndpointsCoverCanonicalMultipartAndRequestStrings() throws Exception {
        UUID c = UUID.randomUUID();
        contributions.submitApplication(c, "tester");
        contributions.approve(c, "owner");

        MockPart meta = SampleApiTest.meta(Map.of("contributorId", c.toString(), "variety", "MINI"));
        MockPart photo = SampleApiTest.file("appearance", "a.jpg", "image/jpeg", utf8("jpeg-bytes"));
        mvc.perform(multipart(BASE).part(meta, photo)).andExpect(status().isUnauthorized());
        // Assertion over a different photo is refused.
        MockPart otherPhoto = SampleApiTest.file("appearance", "a.jpg", "image/jpeg", utf8("other-bytes"));
        mvc.perform(signed(multipart(BASE).part(meta, photo), multipartCanonical(BASE, meta, otherPhoto)))
                .andExpect(status().isUnauthorized());
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM samples WHERE contributor_id = ?",
                Integer.class, c));

        String body = mvc.perform(signed(multipart(BASE).part(meta, photo), multipartCanonical(BASE, meta, photo)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        long id = json.readTree(body).get("id").asLong();

        String partsPath = BASE + "/" + id + "/parts";
        MockPart recording = SampleApiTest.file("recording", "r.wav", "audio/wav", utf8("wav-bytes"));
        mvc.perform(signed(multipart(partsPath + "?contributorId=" + c).part(recording),
                        multipartCanonical(partsPath, recording)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.completeness.recording").value(true));

        String list = BASE + "?contributorId=" + c;
        mvc.perform(get(list)).andExpect(status().isUnauthorized());
        mvc.perform(signed(get(list), utf8("GET " + list))).andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));
        String one = BASE + "/" + id + "?contributorId=" + c;
        mvc.perform(signed(get(one), utf8("GET " + one))).andExpect(status().isOk());
        // A GET assertion cannot be replayed as a DELETE.
        mvc.perform(signed(delete(one), utf8("GET " + one))).andExpect(status().isUnauthorized());
        mvc.perform(signed(delete(one), utf8("DELETE " + one))).andExpect(status().isNoContent());
    }
}

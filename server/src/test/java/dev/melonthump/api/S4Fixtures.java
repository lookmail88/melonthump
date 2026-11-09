package dev.melonthump.api;

import static dev.melonthump.api.SampleApiTest.file;
import static dev.melonthump.api.SampleApiTest.meta;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.ContributionService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.mock.web.MockPart;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;

/** S4 test fixtures: contributors and samples created through the real S1/S2 paths. */
final class S4Fixtures {

    static final ObjectMapper JSON = new ObjectMapper();

    private final MockMvc mvc;
    private final ContributionService contributions;

    S4Fixtures(MockMvc mvc, ContributionService contributions) {
        this.mvc = mvc;
        this.contributions = contributions;
    }

    UUID pendingContributor() {
        UUID id = UUID.randomUUID();
        contributions.submitApplication(id, "s4 test contributor");
        return id;
    }

    UUID approvedContributor() {
        UUID id = pendingContributor();
        contributions.approve(id, "owner");
        return id;
    }

    static byte[] bytes(int n, int seed) {
        byte[] b = new byte[n];
        for (int i = 0; i < n; i++) {
            b[i] = (byte) (i * 13 + seed);
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

    private static Map<String, Object> metaMap(UUID c, boolean withFeedback) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", c.toString());
        m.put("variety", "SEEDLESS");
        if (withFeedback) {
            Map<String, Object> f = new LinkedHashMap<>();
            f.put("score", 72);
            f.put("tasteTags", List.of("SWEET"));
            f.put("bandTruth", "RIPE");
            m.put("feedback", f);
        }
        return m;
    }

    long completeSample(UUID c) throws Exception {
        return body(submit(meta(metaMap(c, true)),
                file("appearance", "a.jpg", "image/jpeg", bytes(300, 1)),
                file("recording", "r.m4a", "audio/m4a", bytes(500, 2)),
                file("cutOpen", "c.png", "image/png", bytes(400, 3)))
                .andExpect(status().isCreated())).get("id").asLong();
    }

    long incompleteSample(UUID c) throws Exception {
        return body(submit(meta(metaMap(c, false)), file("appearance", "a.jpg", "image/jpeg", bytes(200, 9)))
                .andExpect(status().isCreated())).get("id").asLong();
    }

    static JsonNode body(ResultActions r) throws Exception {
        return JSON.readTree(r.andReturn().getResponse().getContentAsString());
    }
}

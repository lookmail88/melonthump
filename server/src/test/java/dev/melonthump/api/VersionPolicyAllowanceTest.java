package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 1.2.0 allowance-policy fields with the built-in defaults (design
 * values), plus the old-client compatibility guarantee: 1.0.0 / 1.1.0
 * clients and requests without currentVersion get the 1.1.0 response
 * byte for byte.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class VersionPolicyAllowanceTest {

    /** The exact 1.1.0 response body under the test profile (no attestation). */
    static final String LEGACY_BODY_TEMPLATE = "{\"platform\":\"ios\",\"latestVersion\":\"1.0.0\","
            + "\"minSupportedVersion\":\"1.0.0\",\"updateAvailable\":%s,\"forceUpdate\":%s,"
            + "\"updateUrl\":\"https://apps.apple.com/us/app/melonthump/id6825623861\","
            + "\"creditPerAd\":1,\"promoEndsAtEpochMillis\":null}";

    @Autowired
    private MockMvc mvc;

    private String body(String currentVersion) throws Exception {
        var request = get("/api/v1/version/getclientversion");
        if (currentVersion != null) {
            request = request.param("currentVersion", currentVersion);
        }
        return mvc.perform(request).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
    }

    @Test
    void legacyClientsReceiveByteIdenticalResponse() throws Exception {
        assertEquals(String.format(LEGACY_BODY_TEMPLATE, false, false), body(null));
        assertEquals(String.format(LEGACY_BODY_TEMPLATE, false, false), body("1.0.0"));
        assertEquals(String.format(LEGACY_BODY_TEMPLATE, false, false), body("1.1.0"));
        assertEquals(String.format(LEGACY_BODY_TEMPLATE, false, false), body("1.1.9"));
        assertEquals(String.format(LEGACY_BODY_TEMPLATE, true, true), body("0.9.0"));
    }

    @Test
    void modernClientGetsDesignDefaults() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "1.2.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.creditPerAd").value(1))
                .andExpect(jsonPath("$.initialFreeThumps").value(2))
                .andExpect(jsonPath("$.sessionUnlockEnabled").value(true))
                .andExpect(jsonPath("$.adFreeSessionCreditPrice").value(1))
                // Not configured in the test profile -> omitted, never null.
                .andExpect(jsonPath("$.testflightVersion").doesNotExist())
                .andExpect(jsonPath("$.productVersion").doesNotExist())
                .andExpect(jsonPath("$.rewardedAdUnitId").doesNotExist());
    }

    @Test
    void laterClientsAlsoGetTheFields() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "1.10.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.initialFreeThumps").value(2));
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "2.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sessionUnlockEnabled").value(true));
    }

    @Test
    void configParsingFallsBackToDesignValues() {
        assertEquals(2, VersionController.parseInt("", 0, 2));
        assertEquals(2, VersionController.parseInt("abc", 0, 2));
        assertEquals(2, VersionController.parseInt("-1", 0, 2));
        assertEquals(0, VersionController.parseInt("0", 0, 2));
        assertEquals(1, VersionController.parseInt("0", 1, 1));
        assertEquals(7, VersionController.parseInt(" 7 ", 0, 2));
        assertEquals(true, VersionController.parseBoolean("yes", true));
        assertEquals(false, VersionController.parseBoolean("FALSE", true));
    }
}

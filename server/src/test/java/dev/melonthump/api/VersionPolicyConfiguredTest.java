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
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 1.2.0 allowance-policy fields driven by configuration (the same keys
 * the k8s env overrides), and legacy clients unaffected by them.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "melonthump.client.initial-free-thumps=3",
        "melonthump.client.session-unlock-enabled=false",
        "melonthump.client.ad-free-session-credit-price=2",
        "melonthump.client.testflight-version=1.2.0",
        "melonthump.client.product-version=1.1.0",
        "spring.datasource.url=jdbc:h2:mem:melonthump-policy-cfg;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1"
})
class VersionPolicyConfiguredTest {

    @Autowired
    private MockMvc mvc;

    @Test
    void modernClientSeesConfiguredValues() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "1.2.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.initialFreeThumps").value(3))
                .andExpect(jsonPath("$.sessionUnlockEnabled").value(false))
                .andExpect(jsonPath("$.adFreeSessionCreditPrice").value(2))
                .andExpect(jsonPath("$.testflightVersion").value("1.2.0"))
                .andExpect(jsonPath("$.productVersion").value("1.1.0"));
    }

    @Test
    void legacyClientsStillByteIdentical() throws Exception {
        String expected = String.format(VersionPolicyAllowanceTest.LEGACY_BODY_TEMPLATE, false, false);
        for (String v : new String[] {"1.0.0", "1.1.0"}) {
            String body = mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", v))
                    .andExpect(status().isOk())
                    .andReturn().getResponse().getContentAsString();
            assertEquals(expected, body, "client " + v);
        }
    }
}

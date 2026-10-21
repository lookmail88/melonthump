package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class VersionControllerTest {

    @Autowired
    private MockMvc mvc;

    @Test
    void policyWithoutCurrentVersion() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.platform").value("ios"))
                .andExpect(jsonPath("$.latestVersion").value("1.0.0"))
                .andExpect(jsonPath("$.minSupportedVersion").value("1.0.0"))
                .andExpect(jsonPath("$.updateAvailable").value(false))
                .andExpect(jsonPath("$.forceUpdate").value(false));
    }

    @Test
    void currentVersionAtMinimumIsNotForced() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "1.0.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.updateAvailable").value(false))
                .andExpect(jsonPath("$.forceUpdate").value(false));
    }

    @Test
    void olderCurrentVersionIsForced() throws Exception {
        mvc.perform(get("/api/v1/version/getclientversion").param("currentVersion", "0.9.0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.updateAvailable").value(true))
                .andExpect(jsonPath("$.forceUpdate").value(true));
    }

    @Test
    void compareVersionsOrdersSegmentsNumerically() {
        assertTrue(VersionController.compareVersions("1.0.0", "1.0.1") < 0);
        assertTrue(VersionController.compareVersions("1.10.0", "1.9.0") > 0);
        assertEquals(0, VersionController.compareVersions("1.0", "1.0.0"));
        assertTrue(VersionController.compareVersions("2", "1.9.9") > 0);
    }
}

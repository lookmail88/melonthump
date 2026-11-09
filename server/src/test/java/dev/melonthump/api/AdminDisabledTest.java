package dev.melonthump.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/** With melonthump.admin.enabled=false (the production default) the admin surface does not exist. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:melonthump-admin-off;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "melonthump.admin.enabled=false"})
class AdminDisabledTest {

    @Autowired
    private MockMvc mvc;

    @Test
    void adminEndpointsAre404WhenDisabled() throws Exception {
        mvc.perform(get("/api/admin/applications")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/applications/" + UUID.randomUUID() + "/approve"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/contributors/" + UUID.randomUUID() + "/revoke"))
                .andExpect(status().isNotFound());
        // S3 admin surface is behind the same switch.
        mvc.perform(get("/api/admin/samples")).andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/samples/1")).andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/samples/1/files/1")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/samples/1/approve")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/samples/1/return")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/samples/1/void")).andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/contributors/" + UUID.randomUUID() + "/adfree")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/contributors/" + UUID.randomUUID() + "/adfree/grants"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/contributors/" + UUID.randomUUID() + "/exemption"))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/exemptions")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/exemptions")).andExpect(status().isNotFound());
        mvc.perform(delete("/api/admin/exemptions/x")).andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/audit")).andExpect(status().isNotFound());
        // S4 admin API surface is behind the same switch.
        mvc.perform(get("/api/admin/settings")).andExpect(status().isNotFound());
        mvc.perform(put("/api/admin/settings")).andExpect(status().isNotFound());
        mvc.perform(delete("/api/admin/settings/credit_per_ad")).andExpect(status().isNotFound());
        mvc.perform(get("/api/admin/overview")).andExpect(status().isNotFound());
        mvc.perform(post("/api/admin/samples/1/preliminary-review")).andExpect(status().isNotFound());
    }

    @Test
    void adminPageIsServedEvenWhenTheApiIsDisabled() throws Exception {
        // The page holds no data; it shows an "admin API disabled" state from the 404s above.
        mvc.perform(get("/admin/index.html")).andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML));
        mvc.perform(get("/admin/admin.js")).andExpect(status().isOk());
        mvc.perform(get("/admin/")).andExpect(status().isOk()).andExpect(forwardedUrl("/admin/index.html"));
    }
}

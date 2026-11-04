package dev.melonthump;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Branding for the generated OpenAPI document / Swagger UI.
 * (Title: "MelonThump API"; previously the springdoc default
 * "OpenAPI definition" / "v0" was served.)
 *
 * The version shown is the API contract version (the /api/v1 line),
 * not the server build version, so it does not rot with each release.
 */
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI melonthumpOpenAPI() {
        return new OpenAPI().info(new Info()
                .title("MelonThump API")
                .description("MelonThump server API: client version policy, "
                        + "App Attest gating, and anonymous usage statistics.")
                .version("v1"));
    }
}

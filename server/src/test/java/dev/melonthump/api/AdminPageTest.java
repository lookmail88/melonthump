package dev.melonthump.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

/**
 * S4 admin page: the static shell and its assets are served over real
 * HTTP at /admin/, with a same-origin CSP, and reference no external URL
 * of any kind (no CDN, no remote font / script / style / image).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-s4-page;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AdminPageTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).build();

    private HttpResponse<String> fetch(String path) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).GET().build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private static String contentType(HttpResponse<?> r) {
        return r.headers().firstValue("Content-Type").orElse("").toLowerCase(Locale.ROOT);
    }

    @Test
    void shellAndAssetsAreServed() throws Exception {
        HttpResponse<String> shell = fetch("/admin/");
        assertEquals(200, shell.statusCode());
        assertTrue(contentType(shell).startsWith("text/html"), contentType(shell));
        assertTrue(shell.body().contains("<script src=\"admin.js\" defer></script>"));
        assertTrue(shell.body().contains("<link rel=\"stylesheet\" href=\"admin.css\">"));
        String csp = shell.headers().firstValue("Content-Security-Policy").orElse("");
        assertTrue(csp.contains("default-src 'none'") && csp.contains("script-src 'self'"), csp);
        assertEquals("nosniff", shell.headers().firstValue("X-Content-Type-Options").orElse(""));

        HttpResponse<String> index = fetch("/admin/index.html");
        assertEquals(200, index.statusCode());
        assertEquals(shell.body(), index.body());

        HttpResponse<String> js = fetch("/admin/admin.js");
        assertEquals(200, js.statusCode());
        assertTrue(contentType(js).contains("javascript"), contentType(js));
        HttpResponse<String> css = fetch("/admin/admin.css");
        assertEquals(200, css.statusCode());
        assertTrue(contentType(css).startsWith("text/css"), contentType(css));

        HttpResponse<String> bare = fetch("/admin");
        assertEquals(302, bare.statusCode());
        assertTrue(bare.headers().firstValue("Location").orElse("").endsWith("/admin/"));
    }

    private static final Pattern SCHEME = Pattern.compile("(?i)\\b(https?|wss?|ftp):");
    private static final Pattern PROTOCOL_RELATIVE = Pattern.compile("[\"'(=]\\s*//");
    private static final Pattern HTML_REF = Pattern.compile("(?i)\\b(?:src|href|action|poster)\\s*=\\s*\"([^\"]*)\"");

    @Test
    void pageReferencesNoExternalUrls() throws Exception {
        for (String path : List.of("/admin/index.html", "/admin/admin.js", "/admin/admin.css")) {
            String body = fetch(path).body();
            assertFalse(SCHEME.matcher(body).find(), path + " contains an absolute URL scheme");
            assertFalse(PROTOCOL_RELATIVE.matcher(body).find(), path + " contains a protocol-relative URL");
            assertFalse(body.toLowerCase(Locale.ROOT).contains("@import"), path + " imports a stylesheet");
        }
        String html = fetch("/admin/index.html").body();
        Matcher m = HTML_REF.matcher(html);
        int refs = 0;
        while (m.find()) {
            String ref = m.group(1);
            refs++;
            assertTrue(ref.startsWith("#") || ref.equals("data:,") || ref.matches("[a-z]+\\.(js|css)"),
                    "unexpected reference in the shell: " + ref);
        }
        assertTrue(refs >= 3);
        String js = fetch("/admin/admin.js").body();
        // Every fetch goes to a same-origin path.
        Matcher api = Pattern.compile("api\\('(?:GET|POST|PUT|DELETE)',\\s*'?([^,)]*)").matcher(js);
        while (api.find()) {
            String target = api.group(1).strip();
            assertTrue(target.startsWith("API") || target.startsWith("'/api/") || target.startsWith("/api/"),
                    "non-relative fetch target: " + target);
        }
    }
}

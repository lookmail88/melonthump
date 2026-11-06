package dev.melonthump.api;

import dev.melonthump.store.InviteStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * Tiny public landing page for shared invite links (design doc 1.2.0 §3;
 * decided with the owner: a custom melonthump:// link plus this page, no
 * Associated Domains entitlement). It shows the code, an "open in app"
 * link, and the App Store link. Opening it records nothing.
 */
@RestController
public class InviteLandingController {

    private final InviteStore invites;
    private final String storeUrl;

    public InviteLandingController(InviteStore invites,
                                   @Value("${melonthump.client.update-url:}") String storeUrl) {
        this.invites = invites;
        this.storeUrl = storeUrl;
    }

    @GetMapping(value = "/invite/{code}", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> landing(@PathVariable String code) {
        String normalized = InviteStore.normalizeCode(code);
        if (normalized == null || invites.findInviterByCode(normalized).isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).contentType(MediaType.TEXT_HTML)
                    .body(page("Invite not found", "<p>This invite link is not valid.</p>"));
        }
        // normalized is restricted to [A-Z2-9]{8}: safe to embed verbatim.
        String body = "<p>You've been invited to MelonThump — thump a watermelon, know if it's ripe.</p>"
                + "<p>Your invite code</p><p class=\"code\">" + normalized + "</p>"
                + "<p><a class=\"btn\" href=\"melonthump://invite?code=" + normalized + "\">Open in MelonThump</a></p>"
                + (storeUrl.isBlank() ? "" : "<p><a href=\"" + escape(storeUrl) + "\">Get MelonThump on the App Store</a></p>")
                + "<p class=\"hint\">Already installed? Tap \"Open in MelonThump\", or enter the code "
                + "from the Invite button in the app before your first thump.</p>";
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(page("MelonThump invite", body));
    }

    private static String page(String title, String body) {
        return "<!doctype html><html><head><meta charset=\"utf-8\">"
                + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                + "<title>" + title + "</title><style>"
                + "body{font-family:-apple-system,system-ui,sans-serif;background:#BEE0A7;color:#2E4420;"
                + "text-align:center;padding:40px 20px}.code{font-size:34px;font-weight:700;letter-spacing:4px}"
                + ".btn{display:inline-block;background:#3E6B1E;color:#fff;padding:14px 28px;border-radius:999px;"
                + "text-decoration:none;font-weight:600}.hint{font-size:13px;color:#5A7350}"
                + "</style></head><body><h1>MelonThump</h1>" + body + "</body></html>";
    }

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }
}

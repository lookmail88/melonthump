package dev.melonthump.api;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * Audit actor for {@code /api/admin/**} writes (design doc 2.0 §7 item 11:
 * "who — the Cloudflare Access identity"). In production Cloudflare
 * Access sits in front of the admin surface and adds
 * {@value #ACCESS_EMAIL_HEADER} to every request it lets through; when
 * that header is present and non-blank it is the actor. Otherwise the
 * caller-specific fallback applies ({@value #OWNER} for the owner
 * actions, {@value #PEPPER} for preliminary review), which keeps the
 * pre-S4 behaviour for local / QA boots without Access.
 *
 * <p>The server does no authentication of its own (no login, no stored
 * password): the header is trusted exactly as far as the edge in front
 * of {@code /api/admin/**} is trusted, which is why the admin API stays
 * behind {@code melonthump.admin.enabled}.
 */
final class AdminActor {

    static final String ACCESS_EMAIL_HEADER = "Cf-Access-Authenticated-User-Email";
    static final String OWNER = "owner";
    static final String PEPPER = "pepper";

    /** audit_log.actor is VARCHAR(128). */
    static final int MAX_LENGTH = 128;

    private AdminActor() {
    }

    /** The Access email of the current request, else {@value #OWNER}. */
    static String current() {
        return current(OWNER);
    }

    /** The Access email of the current request, else {@code fallback}. */
    static String current(String fallback) {
        RequestAttributes attrs = RequestContextHolder.getRequestAttributes();
        if (attrs instanceof ServletRequestAttributes sra) {
            return resolve(sra.getRequest(), fallback);
        }
        return fallback;
    }

    static String resolve(HttpServletRequest request, String fallback) {
        String email = request.getHeader(ACCESS_EMAIL_HEADER);
        if (email == null || email.isBlank()) {
            return fallback;
        }
        String v = email.strip();
        return v.length() > MAX_LENGTH ? v.substring(0, MAX_LENGTH) : v;
    }
}

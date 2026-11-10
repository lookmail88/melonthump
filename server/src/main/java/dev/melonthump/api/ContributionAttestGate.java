package dev.melonthump.api;

import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * App Attest gate for every {@code /api/v1/contributions/**} endpoint
 * (design doc 2.0 §5 item 6). Same verification as the invite / stats
 * endpoints ({@link AssertionService}: enrolled key, accepted
 * environment, fresh single-use challenge, valid signature, strictly
 * increasing counter), and the same dev-only simulator bypass
 * ({@code X-Attest-Bypass: simulator}, honoured only when
 * {@code melonthump.attest.debug-bypass-enabled=true}: the dev manifest,
 * the {@code test} and {@code qa} profiles).
 *
 * <p>What the assertion's client data covers (the client hashes SHA-256
 * of exactly these bytes, as for the existing endpoints):
 * <ul>
 *   <li>JSON POST: the exact request body bytes (as invite / stats).</li>
 *   <li>GET / DELETE (no body): the canonical request string
 *       {@code "<METHOD> <path>?<raw query>"} (as the version policy GET),
 *       e.g. {@code GET /api/v1/contributions/status?contributorId=…};
 *       without a query string the {@code ?} is omitted.</li>
 *   <li>multipart POST: the canonical multipart string — the line
 *       {@code "<METHOD> <path>"} followed by one line
 *       {@code "<part name>:<lowercase hex SHA-256 of the part bytes>"} per
 *       part in request order, joined with {@code '\n'} (no trailing
 *       newline). The raw multipart body is not used because its boundary
 *       framing is not reproducible on the server once the container has
 *       parsed it.</li>
 * </ul>
 * Failures throw {@link AttestException} → 401 (ApiExceptionHandler).
 */
@Component
public class ContributionAttestGate {

    public static final String KEY_ID_HEADER = "X-Key-Id";
    public static final String ASSERTION_HEADER = "X-Assertion";
    public static final String CHALLENGE_HEADER = "X-Challenge";

    private final AssertionService assertions;

    public ContributionAttestGate(AssertionService assertions) {
        this.assertions = assertions;
    }

    /** One multipart part as covered by the assertion. */
    public record PartDigest(String name, byte[] sha256) {
    }

    /** Verifies an assertion over {@code payload} (or accepts the enabled simulator bypass). */
    public void verify(HttpServletRequest request, byte[] payload) throws AttestException {
        if (assertions.isDebugBypass(request.getHeader(AssertionService.BYPASS_HEADER))) {
            return;
        }
        assertions.verify(request.getHeader(KEY_ID_HEADER), request.getHeader(ASSERTION_HEADER),
                request.getHeader(CHALLENGE_HEADER), payload);
    }

    /** Gate for body-less requests (GET / DELETE): covers the canonical request string. */
    public void verifyBodiless(HttpServletRequest request) throws AttestException {
        verify(request, canonicalRequestString(request).getBytes(StandardCharsets.UTF_8));
    }

    /** Gate for multipart requests: covers the canonical multipart string. */
    public void verifyMultipart(HttpServletRequest request, List<PartDigest> parts) throws AttestException {
        verify(request, canonicalMultipartString(request.getMethod(), request.getRequestURI(), parts)
                .getBytes(StandardCharsets.UTF_8));
    }

    static String canonicalRequestString(HttpServletRequest request) {
        String query = request.getQueryString();
        return request.getMethod() + " " + request.getRequestURI()
                + (query == null || query.isEmpty() ? "" : "?" + query);
    }

    public static String canonicalMultipartString(String method, String path, List<PartDigest> parts) {
        StringBuilder sb = new StringBuilder(method).append(' ').append(path);
        HexFormat hex = HexFormat.of();
        for (PartDigest p : parts) {
            sb.append('\n').append(p.name()).append(':').append(hex.formatHex(p.sha256()));
        }
        return sb.toString();
    }

    public static byte[] sha256(byte[] bytes) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}

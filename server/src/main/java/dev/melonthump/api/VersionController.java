package dev.melonthump.api;

import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import dev.melonthump.dto.ClientVersionResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import java.nio.charset.StandardCharsets;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/version")
@Tag(name = "version", description = "Client version policy (forced-update gate)")
public class VersionController {

    private final String platform;
    private final String latestVersion;
    private final String minSupportedVersion;
    private final String updateUrl;
    private final int creditPerAd;
    private final Long promoEndsAtEpochMillis;
    private final String rewardedAdUnitId;
    private final AssertionService assertions;

    public VersionController(
            @Value("${melonthump.client.platform:ios}") String platform,
            @Value("${melonthump.client.latest-version:1.0.0}") String latestVersion,
            @Value("${melonthump.client.min-supported-version:1.0.0}") String minSupportedVersion,
            @Value("${melonthump.client.update-url:}") String updateUrl,
            @Value("${melonthump.client.credit-per-ad:1}") int creditPerAd,
            @Value("${melonthump.client.promo-ends-at-epoch-millis:}") String promoEndsAtRaw,
            @Value("${melonthump.client.rewarded-ad-unit-id:}") String rewardedAdUnitId,
            AssertionService assertions) {
        this.platform = platform;
        this.latestVersion = latestVersion;
        this.minSupportedVersion = minSupportedVersion;
        this.updateUrl = updateUrl;
        this.creditPerAd = creditPerAd;
        this.promoEndsAtEpochMillis = parseEpochMillis(promoEndsAtRaw);
        this.rewardedAdUnitId = rewardedAdUnitId;
        this.assertions = assertions;
    }

    /**
     * The canonical request string an assertion for this endpoint covers
     * (GETs have no body): the client hashes SHA-256 of this exact string
     * into its assertion client data. Must match AttestManager on iOS.
     */
    static String canonicalRequestString(String currentVersion) {
        return "GET /api/v1/version/getclientversion?currentVersion="
                + (currentVersion == null ? "" : currentVersion);
    }

    /** Blank or malformed config means "no promo running" — never fail the policy over it. */
    private static Long parseEpochMillis(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return Long.parseLong(raw.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    @Operation(summary = "Get the client version policy",
            description = "Returns the latest and minimum supported client versions. "
                    + "Pass currentVersion to have the server evaluate updateAvailable / forceUpdate for that client.")
    @GetMapping("/getclientversion")
    public ClientVersionResponse getClientVersion(
            @RequestParam(required = false) String currentVersion,
            @RequestHeader(value = "X-Key-Id", required = false) String keyId,
            @RequestHeader(value = "X-Assertion", required = false) String assertion,
            @RequestHeader(value = "X-Challenge", required = false) String challenge,
            @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass) {
        boolean updateAvailable = currentVersion != null
                && compareVersions(currentVersion, latestVersion) < 0;
        boolean forceUpdate = currentVersion != null
                && compareVersions(currentVersion, minSupportedVersion) < 0;
        return new ClientVersionResponse(
                platform, latestVersion, minSupportedVersion, updateAvailable, forceUpdate, updateUrl,
                creditPerAd, promoEndsAtEpochMillis,
                attestedRewardedAdUnitId(currentVersion, keyId, assertion, challenge, bypass));
    }

    /**
     * The rewarded ad unit ID is disclosed only to a request carrying a
     * valid App Attest assertion (or the dev-only simulator bypass).
     * Every failure is silent: the policy itself is never blocked or
     * altered by attestation, so legacy clients get exactly today's
     * response (field absent) — design doc §2 rule 3, §3.1.
     */
    private String attestedRewardedAdUnitId(String currentVersion, String keyId,
                                            String assertion, String challenge, String bypass) {
        if (rewardedAdUnitId == null || rewardedAdUnitId.isBlank()) {
            return null;
        }
        if (assertions.isDebugBypass(bypass)) {
            return rewardedAdUnitId;
        }
        if (keyId == null || assertion == null || challenge == null) {
            return null;
        }
        try {
            assertions.verify(keyId, assertion, challenge,
                    canonicalRequestString(currentVersion).getBytes(StandardCharsets.UTF_8));
            return rewardedAdUnitId;
        } catch (AttestException | RuntimeException e) {
            return null;
        }
    }

    /** Compares dotted numeric versions segment by segment; missing segments count as 0. */
    static int compareVersions(String a, String b) {
        String[] pa = a.split("\\.");
        String[] pb = b.split("\\.");
        int n = Math.max(pa.length, pb.length);
        for (int i = 0; i < n; i++) {
            int va = i < pa.length ? segment(pa[i]) : 0;
            int vb = i < pb.length ? segment(pb[i]) : 0;
            if (va != vb) {
                return Integer.compare(va, vb);
            }
        }
        return 0;
    }

    private static int segment(String s) {
        int end = 0;
        while (end < s.length() && Character.isDigit(s.charAt(end))) {
            end++;
        }
        return end == 0 ? 0 : Integer.parseInt(s.substring(0, end));
    }
}

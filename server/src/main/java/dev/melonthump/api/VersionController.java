package dev.melonthump.api;

import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import dev.melonthump.contrib.AdExemptionService;
import dev.melonthump.contrib.AdminSettingsService;
import dev.melonthump.dto.ClientVersionResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(VersionController.class);

    /** 2.0 optional request header carrying the client's install id (design doc 2.0 §2 item 6). */
    static final String INSTALL_ID_HEADER = "X-Install-Id";

    private final String platform;
    private final String latestVersion;
    private final String minSupportedVersion;
    private final String updateUrl;
    private final String rewardedAdUnitId;
    private final boolean sessionUnlockEnabled;
    private final int adFreeSessionCreditPrice;
    private final String testflightVersion;
    private final String productVersion;
    private final AssertionService assertions;
    private final AdExemptionService exemptions;
    /**
     * S4: creditPerAd, promoEndsAtEpochMillis and initialFreeThumps are the
     * effective admin settings (override, else the same properties / env
     * defaults as before). Only the VALUES can change; the response shape
     * and the per-version gating are untouched. latestVersion and
     * minSupportedVersion stay plain configuration (release process only).
     */
    private final AdminSettingsService settings;

    /** Design values (1.2.0 §3, decided 2026-11-05) — also the fallback for invalid config. */
    static final int DEFAULT_INITIAL_FREE_THUMPS = AdminSettingsService.DEFAULT_INITIAL_FREE_THUMPS;
    static final boolean DEFAULT_SESSION_UNLOCK_ENABLED = true;
    static final int DEFAULT_AD_FREE_SESSION_CREDIT_PRICE = 1;

    public VersionController(
            @Value("${melonthump.client.platform:ios}") String platform,
            @Value("${melonthump.client.latest-version:1.0.0}") String latestVersion,
            @Value("${melonthump.client.min-supported-version:1.0.0}") String minSupportedVersion,
            @Value("${melonthump.client.update-url:}") String updateUrl,
            @Value("${melonthump.client.rewarded-ad-unit-id:}") String rewardedAdUnitId,
            @Value("${melonthump.client.session-unlock-enabled:true}") String sessionUnlockRaw,
            @Value("${melonthump.client.ad-free-session-credit-price:1}") String adFreePriceRaw,
            @Value("${melonthump.client.testflight-version:}") String testflightVersion,
            @Value("${melonthump.client.product-version:}") String productVersion,
            AssertionService assertions,
            AdExemptionService exemptions,
            AdminSettingsService settings) {
        this.platform = platform;
        this.latestVersion = latestVersion;
        this.minSupportedVersion = minSupportedVersion;
        this.updateUrl = updateUrl;
        this.rewardedAdUnitId = rewardedAdUnitId;
        this.sessionUnlockEnabled = parseBoolean(sessionUnlockRaw, DEFAULT_SESSION_UNLOCK_ENABLED);
        this.adFreeSessionCreditPrice = parseInt(adFreePriceRaw, 1, DEFAULT_AD_FREE_SESSION_CREDIT_PRICE);
        this.testflightVersion = blankToNull(testflightVersion);
        this.productVersion = blankToNull(productVersion);
        this.assertions = assertions;
        this.exemptions = exemptions;
        this.settings = settings;
    }

    /**
     * Malformed or out-of-range allowance config falls back to the design
     * value — a typo in a manifest must never break the policy endpoint.
     */
    static int parseInt(String raw, int min, int fallback) {
        return AdminSettingsService.parseInt(raw, min, fallback);
    }

    static boolean parseBoolean(String raw, boolean fallback) {
        if (raw == null) {
            return fallback;
        }
        String v = raw.trim().toLowerCase(java.util.Locale.ROOT);
        if (v.equals("true")) {
            return true;
        }
        if (v.equals("false")) {
            return false;
        }
        return fallback;
    }

    private static String blankToNull(String raw) {
        return raw == null || raw.isBlank() ? null : raw.trim();
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

    @Operation(summary = "Get the client version policy",
            description = "Returns the latest and minimum supported client versions. "
                    + "Pass currentVersion to have the server evaluate updateAvailable / forceUpdate for that client.")
    @GetMapping("/getclientversion")
    public ClientVersionResponse getClientVersion(
            @RequestParam(required = false) String currentVersion,
            @RequestHeader(value = "X-Key-Id", required = false) String keyId,
            @RequestHeader(value = "X-Assertion", required = false) String assertion,
            @RequestHeader(value = "X-Challenge", required = false) String challenge,
            @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass,
            @RequestHeader(value = INSTALL_ID_HEADER, required = false) String installId) {
        boolean updateAvailable = currentVersion != null
                && compareVersions(currentVersion, latestVersion) < 0;
        boolean forceUpdate = currentVersion != null
                && compareVersions(currentVersion, minSupportedVersion) < 0;
        // 1.2.0 fields go only to clients that declare 1.2.0+; legacy
        // clients (and requests without currentVersion) get exactly the
        // 1.1.0 response — the new fields are null and omitted.
        boolean modern = currentVersion != null
                && compareVersions(currentVersion, ClientVersionResponse.ALLOWANCE_FIELDS_SINCE) >= 0;
        AdminSettingsService.Effective effective = settings.effective();
        return new ClientVersionResponse(
                platform, latestVersion, minSupportedVersion, updateAvailable, forceUpdate, updateUrl,
                effective.creditPerAd(), effective.promoEndsAtEpochMillis(),
                attestedRewardedAdUnitId(currentVersion, keyId, assertion, challenge, bypass),
                modern ? effective.initialFreeThumps() : null,
                modern ? sessionUnlockEnabled : null,
                modern ? adFreeSessionCreditPrice : null,
                modern ? testflightVersion : null,
                modern ? productVersion : null,
                adExempt(currentVersion, installId));
    }

    /**
     * 2.0 adExempt (design doc 2.0 §2 item 6): only for clients reporting
     * 2.0.0+, whose X-Install-Id is looked up in the owner allowlist; for
     * older clients (and requests without currentVersion) the header is
     * ignored, nothing is looked up, and the field stays absent. A lookup
     * failure answers false — it never breaks the policy.
     */
    private Boolean adExempt(String currentVersion, String installId) {
        if (currentVersion == null
                || compareVersions(currentVersion, ClientVersionResponse.AD_EXEMPT_SINCE) < 0) {
            return null;
        }
        try {
            return exemptions.isExempt(installId);
        } catch (RuntimeException e) {
            log.warn("adExempt lookup failed; answering false", e);
            return false;
        }
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

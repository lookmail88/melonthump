package dev.melonthump.api;

import dev.melonthump.dto.ClientVersionResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
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

    public VersionController(
            @Value("${melonthump.client.platform:ios}") String platform,
            @Value("${melonthump.client.latest-version:1.0.0}") String latestVersion,
            @Value("${melonthump.client.min-supported-version:1.0.0}") String minSupportedVersion,
            @Value("${melonthump.client.update-url:}") String updateUrl,
            @Value("${melonthump.client.credit-per-ad:1}") int creditPerAd,
            @Value("${melonthump.client.promo-ends-at-epoch-millis:}") String promoEndsAtRaw) {
        this.platform = platform;
        this.latestVersion = latestVersion;
        this.minSupportedVersion = minSupportedVersion;
        this.updateUrl = updateUrl;
        this.creditPerAd = creditPerAd;
        this.promoEndsAtEpochMillis = parseEpochMillis(promoEndsAtRaw);
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
            @RequestParam(required = false) String currentVersion) {
        boolean updateAvailable = currentVersion != null
                && compareVersions(currentVersion, latestVersion) < 0;
        boolean forceUpdate = currentVersion != null
                && compareVersions(currentVersion, minSupportedVersion) < 0;
        return new ClientVersionResponse(
                platform, latestVersion, minSupportedVersion, updateAvailable, forceUpdate, updateUrl,
                creditPerAd, promoEndsAtEpochMillis);
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

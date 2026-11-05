package dev.melonthump.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Client version policy: what the app should run, and whether it must update")
public record ClientVersionResponse(
        @Schema(description = "Client platform this policy applies to", example = "ios")
        String platform,
        @Schema(description = "Latest released client version", example = "1.0.0")
        String latestVersion,
        @Schema(description = "Oldest client version still allowed to use the API", example = "1.0.0")
        String minSupportedVersion,
        @Schema(description = "True when currentVersion (if supplied) is below latestVersion")
        boolean updateAvailable,
        @Schema(description = "True when currentVersion (if supplied) is below minSupportedVersion: the app must update")
        boolean forceUpdate,
        @Schema(description = "Where to send the user to update (store / TestFlight URL); empty until distribution is set up")
        String updateUrl,
        @Schema(description = "Credits granted for one completed rewarded ad; -1 means a free day: unlimited use, no ads shown", example = "1")
        int creditPerAd,
        @Schema(description = "End of the launch promo window as epoch milliseconds; null when no promo is running. "
                + "During the promo, the first thump after each fresh app launch requires one completed "
                + "rewarded ad, which unlocks unlimited use until the app exits (relaunching gates again, "
                + "even on the same day); credits are neither needed nor spent",
                example = "1767225599000", nullable = true)
        Long promoEndsAtEpochMillis,
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "Production rewarded ad unit ID, issued ONLY to requests carrying a valid "
                + "App Attest assertion (1.1.0+); the field is entirely absent otherwise, so legacy "
                + "clients see a byte-identical response", nullable = true)
        String rewardedAdUnitId,
        // ---- 1.2.0 additive fields (design doc 1.2.0 §2/§3) ----------------
        // Delivered ONLY to clients reporting currentVersion >= 1.2.0; for
        // every other request they are null and therefore absent from the
        // JSON, so 1.0.0 / 1.1.0 clients receive a byte-identical response.
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "1.2.0+: number of initial free thumps per user after the promotion "
                + "(the first analysis is never charged; a one-time grant of initialFreeThumps - 1 "
                + "credits covers the rest)", example = "2", nullable = true)
        Integer initialFreeThumps,
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "1.2.0+: whether the session-unlock gate applies after the free thumps "
                + "(true: one rewarded ad, or adFreeSessionCreditPrice credits, unlocks unlimited thumps "
                + "until the app exits; false: no gate at all — unlimited use, no ads)",
                example = "true", nullable = true)
        Boolean sessionUnlockEnabled,
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "1.2.0+: credits spent to unlock one app session without an ad",
                example = "1", nullable = true)
        Integer adFreeSessionCreditPrice,
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "1.2.0+: the client version currently in TestFlight; absent when not configured",
                example = "1.2.0", nullable = true)
        String testflightVersion,
        @JsonInclude(JsonInclude.Include.NON_NULL)
        @Schema(description = "1.2.0+: the client version currently released on the App Store; absent when not configured",
                example = "1.1.0", nullable = true)
        String productVersion) {

    /** First client version that receives the 1.2.0 policy fields. */
    public static final String ALLOWANCE_FIELDS_SINCE = "1.2.0";
}

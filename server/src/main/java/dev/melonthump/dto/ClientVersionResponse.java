package dev.melonthump.dto;

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
        int creditPerAd) {
}

package dev.melonthump.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Wire shapes for the usage-stats endpoints (design doc §3.3/§3.4). */
public final class StatsDtos {

    private StatsDtos() {
    }

    @Schema(description = "One client event. Closed type set; no free-text fields, slot is a logical name, never a real ad unit ID")
    public record EventDto(
            @Schema(description = "Client-generated per-event UUID; makes uploads idempotent")
            UUID eventId,
            @Schema(description = "analysis_completed / ad_requested / ad_loaded / ad_load_failed / ad_shown / ad_rewarded / ad_dismissed")
            String type,
            @Schema(description = "Client occurrence time, epoch milliseconds (UTC)")
            long clientTs,
            @Schema(description = "analysis_completed only: UNRIPE / RIPE / OVERRIPE / UNKNOWN")
            String verdict,
            @Schema(description = "Ad events only: logical slot name, e.g. rewarded_main")
            String slot,
            @Schema(description = "ad_requested only: server / test_fallback")
            String unitSource,
            @Schema(description = "ad_load_failed only: ad SDK error code")
            Integer errorCode) {
    }

    @Schema(description = "Batch upload body for POST /api/v1/stats/events")
    public record EventsRequest(
            UUID installId,
            @Schema(description = "Per-launch session UUID")
            UUID sessionId,
            List<EventDto> events,
            @Schema(description = "Client app marketing version, e.g. 1.1.0 (client-reported; the X-App-Version header is the fallback carrier)")
            String appVersion,
            @Schema(description = "Distribution channel computed on-device from the App Store receipt: xcode / testflight / appstore (client-reported, analytics only)")
            String channel) {
    }

    @Schema(description = "Upload outcome: how many events were newly stored (duplicates are accepted but counted once)")
    public record EventsResponse(
            int accepted) {
    }

    @Schema(description = "One America/Los_Angeles day of reconciliation aggregates")
    public record SummaryDay(
            String date,
            long analyses,
            Map<String, Long> verdicts,
            long adRequested,
            long adLoaded,
            long adLoadFailed,
            long adShown,
            long adRewarded,
            long adDismissed,
            long activeInstalls,
            @Schema(description = "Distinct active installs per distribution channel (unknown = channel not reported)")
            Map<String, Long> channelInstalls,
            @Schema(description = "Event counts per client app version (unknown = version not reported)")
            Map<String, Long> versionEvents) {
    }

    @Schema(description = "Reconciliation summary (design doc §3.4)")
    public record SummaryResponse(
            List<SummaryDay> days) {
    }
}

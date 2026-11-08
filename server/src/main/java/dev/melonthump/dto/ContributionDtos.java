package dev.melonthump.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/** Wire shapes for the 2.0 contribution and admin endpoints (design doc 2.0 §5 item 6, §2 item 7). */
public final class ContributionDtos {

    private ContributionDtos() {
    }

    @Schema(description = "Contributor application: the Keychain contributor UUID and the enrollment note")
    public record ApplicationRequest(
            @Schema(description = "Anonymous contributor UUID generated on-device at opt-in")
            UUID contributorId,
            @Schema(description = "Enrollment note: who the contributor is (required, 1-1000 chars, owner-only)")
            String note) {
    }

    @Schema(description = "The contributor's application as stored")
    public record ApplicationResponse(
            UUID contributorId,
            @Schema(description = "PENDING / APPROVED / DECLINED / REVOKED")
            String status,
            @Schema(description = "ISO-8601 UTC instant the application was first submitted")
            String createdAt,
            @Schema(description = "ISO-8601 UTC instant of the last status change")
            String updatedAt) {
    }

    @Schema(description = "Contributor self-service standing")
    public record ContributorStatusResponse(
            UUID contributorId,
            @Schema(description = "PENDING / APPROVED / DECLINED / REVOKED")
            String status,
            @Schema(description = "Current ad-free allowance balance (sum of ledger deltas; 0 when none)")
            long adFreeBalance) {
    }

    @Schema(description = "Admin view of one contributor application, including the enrollment note")
    public record AdminApplicationView(
            UUID contributorId,
            @Schema(description = "Enrollment note (owner-only)")
            String note,
            @Schema(description = "PENDING / APPROVED / DECLINED / REVOKED")
            String status,
            String createdAt,
            String updatedAt) {
    }
}

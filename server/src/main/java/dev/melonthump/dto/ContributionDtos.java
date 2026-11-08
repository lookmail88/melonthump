package dev.melonthump.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
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

    // ---- S2: samples ---------------------------------------------------------

    @Schema(description = "Which of the four sample parts have arrived")
    public record Completeness(
            @Schema(description = "At least one appearance photo stored") boolean appearance,
            @Schema(description = "Recording stored") boolean recording,
            @Schema(description = "Cut-open photo stored") boolean cutOpen,
            @Schema(description = "Valid feedback (score + band truth) stored") boolean feedback) {
    }

    @Schema(description = "One sample in the contributor's own list")
    public record SampleSummary(
            long id,
            @Schema(description = "SUBMITTED / APPROVED / RETURNED / VOIDED") String status,
            Completeness completeness,
            @Schema(description = "All four parts present") boolean complete,
            @Schema(description = "Owner's note when RETURNED; null otherwise") String returnReason,
            @Schema(description = "Preset variety (design §7 item 7)") String variety,
            String createdAt,
            String updatedAt) {
    }

    @Schema(description = "Contributor feedback on a sample: the fourth part")
    public record FeedbackView(
            @Schema(description = "0-100") Integer score,
            @Schema(description = "Preset taste tags: CRISP / MEALY / SANDY / JUICY / SWEET / BLAND")
            List<String> tasteTags,
            @Schema(description = "UNRIPE / RIPE / OVERRIPE") String bandTruth) {
    }

    @Schema(description = "One stored material file (no path, no download link)")
    public record SampleFileView(
            @Schema(description = "APPEARANCE / RECORDING / CUT_OPEN") String part,
            @Schema(description = "Lowercase hex SHA-256 of the stored bytes") String sha256,
            long sizeBytes,
            String contentType) {
    }

    @Schema(description = "One sample with its bookkeeping, feedback and file list")
    public record SampleDetail(
            long id,
            UUID contributorId,
            @Schema(description = "SUBMITTED / APPROVED / RETURNED / VOIDED") String status,
            Completeness completeness,
            boolean complete,
            String returnReason,
            String variety,
            Integer weightGrams,
            @Schema(description = "PHOTO_ESTIMATED / MANUAL_ESTIMATE / SCALE_MEASURED") String weightProvenance,
            String source,
            @Schema(description = "ISO-8601 date") String melonDate,
            @Schema(description = "null until feedback has been given") FeedbackView feedback,
            List<SampleFileView> files,
            String createdAt,
            String updatedAt) {
    }
}

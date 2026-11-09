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
            long adFreeBalance,
            @Schema(description = "S3: true when the owner granted this contributor permanent ad exemption")
            boolean adExemptPermanent) {
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

    // ---- S3: owner review, incentive ledger, exemptions, audit ---------------

    @Schema(description = "One sample in the admin review list")
    public record AdminSampleSummary(
            long id,
            UUID contributorId,
            @Schema(description = "SUBMITTED / APPROVED / RETURNED / VOIDED") String status,
            Completeness completeness,
            @Schema(description = "All four parts present") boolean complete,
            @Schema(description = "Owner's note when RETURNED; null otherwise") String returnReason,
            String variety,
            String createdAt,
            String updatedAt,
            @Schema(description = "S4: Pepper's preliminary recommendation (SUGGEST_APPROVE / SUGGEST_RETURN / "
                    + "FLAG_OWNER); null until reviewed", nullable = true)
            String pepperRecommendation,
            @Schema(description = "S4: Pepper's note (e.g. a drafted return reason); may be null", nullable = true)
            String pepperNote,
            @Schema(description = "S4: ISO-8601 UTC instant of the preliminary review; null until reviewed",
                    nullable = true)
            String pepperReviewedAt) {
    }

    @Schema(description = "One stored material file in the admin detail: the S2 file view plus the row id "
            + "used by the admin download endpoint")
    public record AdminSampleFileView(
            @Schema(description = "File id for GET /api/admin/samples/{id}/files/{fileId}") long id,
            @Schema(description = "APPEARANCE / RECORDING / CUT_OPEN") String part,
            String sha256,
            long sizeBytes,
            String contentType) {
    }

    @Schema(description = "Admin sample detail: the S2 sample detail shape, with file ids for download")
    public record AdminSampleDetail(
            long id,
            UUID contributorId,
            String status,
            Completeness completeness,
            boolean complete,
            String returnReason,
            String variety,
            Integer weightGrams,
            String weightProvenance,
            String source,
            String melonDate,
            FeedbackView feedback,
            List<AdminSampleFileView> files,
            String createdAt,
            String updatedAt,
            @Schema(description = "S4: Pepper's preliminary recommendation; null until reviewed", nullable = true)
            String pepperRecommendation,
            @Schema(description = "S4: Pepper's note; may be null", nullable = true)
            String pepperNote,
            @Schema(description = "S4: ISO-8601 UTC instant of the preliminary review", nullable = true)
            String pepperReviewedAt,
            @Schema(description = "FIX12 (legacy): on-device Vision `watermelon` confidence (0-1), best of the "
                    + "appearance photos, as sent by a FIX12 client; null when not sent", nullable = true)
            Double visionWatermelon,
            @Schema(description = "FIX12: on-device Vision `watermelon` confidence (0-1) of the cut-open photo; "
                    + "null when not sent", nullable = true)
            Double visionCutopenWatermelon,
            @Schema(description = "FIX12B: on-device Vision `watermelon` confidence (0-1), best of the whole-melon "
                    + "photos; null when not sent", nullable = true)
            Double visionWholeWatermelon,
            @Schema(description = "FIX12B: on-device Vision `watermelon` confidence (0-1), best of the rind "
                    + "close-up photos; null when not sent", nullable = true)
            Double visionRindWatermelon) {
    }

    @Schema(description = "Result of a manual ad-free grant / revocation")
    public record AdFreeGrantResponse(
            UUID contributorId,
            @Schema(description = "The delta the owner asked for") int requestedDelta,
            @Schema(description = "The delta actually applied (a negative delta stops at a zero balance)")
            int appliedDelta,
            @Schema(description = "Balance after the grant") long balance) {
    }

    @Schema(description = "One ad-free ledger row")
    public record LedgerEntryView(
            long id,
            int delta,
            @Schema(description = "SAMPLE_APPROVED / VOID_CLAWBACK / ADMIN_GRANT / ADMIN_REVOKE / SESSION_UNLOCK")
            String reason,
            @Schema(description = "Sample id for SAMPLE_APPROVED / VOID_CLAWBACK rows; null otherwise")
            String referenceId,
            String createdAt) {
    }

    @Schema(description = "A contributor's ad-free ledger, newest first")
    public record AdFreeLedgerResponse(
            UUID contributorId,
            long balance,
            List<LedgerEntryView> entries,
            @Schema(description = "Permanent ad exemption flag (spending is skipped while true)")
            boolean adExemptPermanent) {
    }

    @Schema(description = "A contributor's permanent ad exemption")
    public record ContributorExemptionView(
            UUID contributorId,
            @Schema(description = "PENDING / APPROVED / DECLINED / REVOKED") String status,
            boolean adExemptPermanent) {
    }

    @Schema(description = "One install on the owner ad-exemption allowlist")
    public record AdExemptionView(
            String installId,
            String note,
            String createdAt) {
    }

    @Schema(description = "One audit log row")
    public record AuditEntryView(
            long id,
            String actor,
            String action,
            String objectType,
            String objectId,
            @Schema(description = "JSON snapshot before the change, as stored; null for creations") String beforeJson,
            @Schema(description = "JSON snapshot after the change, as stored; null for deletions") String afterJson,
            String createdAt) {
    }

    @Schema(description = "Result of spending one ad-free unit to unlock a session")
    public record AdFreeSpendResponse(
            @Schema(description = "True when one unit was deducted") boolean spent,
            @Schema(description = "True when the contributor is permanently exempt (nothing spent)") boolean exempt,
            @Schema(description = "Balance after the call") long balance) {
    }
}

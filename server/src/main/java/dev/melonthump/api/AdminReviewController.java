package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.PepperRecommendation;
import dev.melonthump.contrib.Sample;
import dev.melonthump.contrib.SampleService.SampleWithFiles;
import dev.melonthump.contrib.SampleReviewService;
import dev.melonthump.contrib.SampleStatus;
import dev.melonthump.dto.ContributionDtos.AdminSampleDetail;
import dev.melonthump.dto.ContributionDtos.AdminSampleFileView;
import dev.melonthump.dto.ContributionDtos.AdminSampleSummary;
import dev.melonthump.dto.ContributionDtos.Completeness;
import dev.melonthump.dto.ContributionDtos.SampleDetail;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Owner sample review (design doc 2.0 §7 items 10-11, admin page B):
 * list / detail / material download, approve, return with a reason,
 * void-mark. Same kill-switch and audit actor as {@link AdminController}.
 */
@RestController
@RequestMapping("/api/admin/samples")
@ConditionalOnProperty(name = "melonthump.admin.enabled", havingValue = "true")
@Tag(name = "admin", description = "Owner console API (behind Cloudflare Access in production)")
public class AdminReviewController {

    private final SampleReviewService review;
    private final ObjectMapper objectMapper;

    public AdminReviewController(SampleReviewService review, ObjectMapper objectMapper) {
        this.review = review;
        this.objectMapper = objectMapper;
    }

    @Operation(summary = "List samples, newest first",
            description = "Optional filters: status (SUBMITTED / APPROVED / RETURNED / VOIDED, case-insensitive), "
                    + "contributorId. limit: default 50, values above 200 are capped at 200.")
    @GetMapping
    public List<AdminSampleSummary> list(@RequestParam(required = false) String status,
                                         @RequestParam(required = false) String contributorId,
                                         @RequestParam(required = false) String limit) {
        SampleStatus s = AdminParams.optionalEnum(status, SampleStatus.class, "status");
        UUID c = contributorId == null || contributorId.isBlank() ? null
                : AdminParams.uuid(contributorId, "contributorId");
        return review.list(s, c, AdminParams.limit(limit)).stream().map(AdminReviewController::summary).toList();
    }

    @Operation(summary = "Sample detail: the contributor-facing detail shape, files carrying their download id")
    @GetMapping("/{sampleId}")
    public AdminSampleDetail detail(@PathVariable String sampleId) {
        return view(review.detail(AdminParams.positiveId(sampleId, "sampleId")));
    }

    @Operation(summary = "Download one material file with its stored content type",
            description = "fileId is the sample_files row id (the same order as the detail's files list). "
                    + "404 for an unknown sample / file or a file of another sample.")
    @GetMapping("/{sampleId}/files/{fileId}")
    public ResponseEntity<Resource> file(@PathVariable String sampleId, @PathVariable String fileId) {
        SampleReviewService.MaterialFile m = review.file(AdminParams.positiveId(sampleId, "sampleId"),
                AdminParams.positiveId(fileId, "fileId"));
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(m.file().getContentType()))
                .contentLength(m.file().getSizeBytes())
                .header(HttpHeaders.CACHE_CONTROL, "no-store")
                .header("X-Content-Type-Options", "nosniff")
                .body(new FileSystemResource(m.path()));
    }

    @Operation(summary = "Approve (SUBMITTED -> APPROVED); a complete sample earns the configured ad-free units once",
            description = "Already APPROVED: 200 no-op. RETURNED / VOIDED: 409.")
    @PostMapping("/{sampleId}/approve")
    public AdminSampleDetail approve(@PathVariable String sampleId) {
        return view(review.approve(AdminParams.positiveId(sampleId, "sampleId"),
                AdminActor.current()));
    }

    @Operation(summary = "Return with a reason (SUBMITTED -> RETURNED)",
            description = "Body {\"reason\": \"...\"}: required, non-blank, at most 500 characters. "
                    + "Already RETURNED: 200 no-op. APPROVED / VOIDED: 409.")
    @PostMapping("/{sampleId}/return")
    public AdminSampleDetail returnSample(@PathVariable String sampleId,
                                     @RequestBody(required = false) byte[] body) {
        long id = AdminParams.positiveId(sampleId, "sampleId");
        String reason = AdminParams.requiredText(AdminParams.object(objectMapper, body), "reason",
                SampleReviewService.MAX_RETURN_REASON_LENGTH);
        return view(review.returnSample(id, reason, AdminActor.current()));
    }

    @Operation(summary = "Void-mark (SUBMITTED / RETURNED / APPROVED -> VOIDED); earned units are clawed back",
            description = "Clawback = min(current balance, earned), never below zero. Already VOIDED: 200 no-op.")
    @PostMapping("/{sampleId}/void")
    public AdminSampleDetail voidSample(@PathVariable String sampleId) {
        return view(review.voidSample(AdminParams.positiveId(sampleId, "sampleId"),
                AdminActor.current()));
    }

    @Operation(summary = "Pepper's preliminary review: attach an advisory recommendation to a sample",
            description = "Body {\"recommendation\": \"SUGGEST_APPROVE\" | \"SUGGEST_RETURN\" | \"FLAG_OWNER\", "
                    + "\"note\": optional, at most 1000 chars}. Replaces any earlier recommendation; never changes "
                    + "the sample status (the owner makes the final call). Audit actor: the Access email when "
                    + "present, else 'pepper'. Unknown sample: 404; bad recommendation: 400.")
    @PostMapping("/{sampleId}/preliminary-review")
    public AdminSampleDetail preliminaryReview(@PathVariable String sampleId,
                                               @RequestBody(required = false) byte[] body) {
        long id = AdminParams.positiveId(sampleId, "sampleId");
        JsonNode json = AdminParams.object(objectMapper, body);
        JsonNode r = json.get("recommendation");
        if (r == null || !r.isTextual() || r.asText().isBlank()) {
            throw AdminParams.bad("recommendation is required (SUGGEST_APPROVE / SUGGEST_RETURN / FLAG_OWNER)");
        }
        PepperRecommendation rec;
        try {
            rec = PepperRecommendation.valueOf(r.asText().strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw AdminParams.bad("recommendation must be SUGGEST_APPROVE / SUGGEST_RETURN / FLAG_OWNER");
        }
        String note = AdminParams.optionalText(json, "note", SampleReviewService.MAX_PEPPER_NOTE_LENGTH);
        return view(review.preliminaryReview(id, rec, note, AdminActor.current(AdminActor.PEPPER)));
    }

    static AdminSampleDetail view(SampleWithFiles r) {
        SampleDetail d = SampleController.detail(r);
        List<AdminSampleFileView> files = r.files().stream()
                .map(f -> new AdminSampleFileView(f.getId(), f.getPart().name(), f.getSha256(), f.getSizeBytes(),
                        f.getContentType()))
                .toList();
        return new AdminSampleDetail(d.id(), d.contributorId(), d.status(), d.completeness(), d.complete(),
                d.returnReason(), d.variety(), d.weightGrams(), d.weightProvenance(), d.source(), d.melonDate(),
                d.feedback(), files, d.createdAt(), d.updatedAt(), pepperRecommendation(r.sample()),
                r.sample().getPepperNote(), instant(r.sample().getPepperReviewedAt()),
                r.sample().getVisionWatermelon(), r.sample().getVisionCutopenWatermelon(),
                r.sample().getVisionWholeWatermelon(), r.sample().getVisionRindWatermelon());
    }

    private static String pepperRecommendation(Sample s) {
        return s.getPepperRecommendation() == null ? null : s.getPepperRecommendation().name();
    }

    private static String instant(java.time.Instant i) {
        return i == null ? null : i.toString();
    }

    static AdminSampleSummary summary(Sample s) {
        return new AdminSampleSummary(s.getId(), s.getContributorId(), s.getStatus().name(),
                new Completeness(s.hasAppearance(), s.hasRecording(), s.hasCutOpen(), s.hasFeedback()),
                s.isComplete(), s.getReturnReason(), s.getVariety().name(),
                s.getCreatedAt().toString(), s.getUpdatedAt().toString(), pepperRecommendation(s), s.getPepperNote(),
                instant(s.getPepperReviewedAt()));
    }
}

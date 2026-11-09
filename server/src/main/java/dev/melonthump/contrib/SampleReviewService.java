package dev.melonthump.contrib;

import dev.melonthump.contrib.SampleService.SampleStateException;
import dev.melonthump.contrib.SampleService.SampleWithFiles;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Owner sample review (design doc 2.0 §7 items 9-11): approve, return
 * with a reason, void-mark; plus the admin sample list, detail and
 * material download. Every decision locks the sample row
 * ({@code PESSIMISTIC_WRITE}, as the S2 appends do), and the status
 * change, its ledger effect and its audit row commit in one transaction.
 *
 * <ul>
 *   <li>approve: SUBMITTED → APPROVED; a complete sample earns the
 *       configured ad-free units once. Already APPROVED: no-op.
 *       RETURNED / VOIDED: refused.</li>
 *   <li>return: SUBMITTED → RETURNED with a reason. Already RETURNED:
 *       no-op. APPROVED / VOIDED: refused.</li>
 *   <li>void: SUBMITTED / RETURNED / APPROVED → VOIDED; earned units are
 *       clawed back down to a zero floor. Already VOIDED: no-op.</li>
 * </ul>
 * No-ops write no audit row and no ledger row.
 */
@Service
public class SampleReviewService {

    public static final String ACTION_APPROVED = "SAMPLE_APPROVED";
    public static final String ACTION_RETURNED = "SAMPLE_RETURNED";
    public static final String ACTION_VOIDED = "SAMPLE_VOIDED";

    /** Longest return reason (characters, after trimming). */
    public static final int MAX_RETURN_REASON_LENGTH = 500;

    private final SampleRepository samples;
    private final SampleFileRepository files;
    private final MaterialStorage storage;
    private final IncentiveService incentives;
    private final AuditLogService audit;

    public SampleReviewService(SampleRepository samples, SampleFileRepository files, MaterialStorage storage,
                               IncentiveService incentives, AuditLogService audit) {
        this.samples = samples;
        this.files = files;
        this.storage = storage;
        this.incentives = incentives;
        this.audit = audit;
    }

    public static final class SampleNotFoundException extends RuntimeException {
        public SampleNotFoundException(long sampleId) {
            super("unknown sample " + sampleId);
        }
    }

    public static final class SampleFileNotFoundException extends RuntimeException {
        public SampleFileNotFoundException(long sampleId, long fileId) {
            super("sample " + sampleId + " has no file " + fileId);
        }
    }

    /** A material file and where its bytes are. */
    public record MaterialFile(SampleFile file, Path path) {
    }

    // ---- queries -------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Sample> list(SampleStatus status, UUID contributorId, int limit) {
        Limit l = Limit.of(limit);
        if (status == null && contributorId == null) {
            return samples.findAllByOrderByCreatedAtDescIdDesc(l);
        }
        if (contributorId == null) {
            return samples.findByStatusOrderByCreatedAtDescIdDesc(status, l);
        }
        if (status == null) {
            return samples.findByContributorIdOrderByCreatedAtDescIdDesc(contributorId, l);
        }
        return samples.findByStatusAndContributorIdOrderByCreatedAtDescIdDesc(status, contributorId, l);
    }

    @Transactional(readOnly = true)
    public SampleWithFiles detail(long sampleId) {
        Sample s = samples.findById(sampleId).orElseThrow(() -> new SampleNotFoundException(sampleId));
        return new SampleWithFiles(s, files.findBySampleIdOrderByIdAsc(sampleId));
    }

    @Transactional(readOnly = true)
    public MaterialFile file(long sampleId, long fileId) {
        samples.findById(sampleId).orElseThrow(() -> new SampleNotFoundException(sampleId));
        SampleFile f = files.findById(fileId)
                .filter(x -> x.getSampleId() == sampleId)
                .orElseThrow(() -> new SampleFileNotFoundException(sampleId, fileId));
        Path path = storage.resolve(f.getStoredPath());
        if (!Files.isRegularFile(path)) {
            throw new SampleFileNotFoundException(sampleId, fileId);
        }
        return new MaterialFile(f, path);
    }

    // ---- decisions -----------------------------------------------------------

    @Transactional
    public SampleWithFiles approve(long sampleId, String actor) {
        Sample s = lock(sampleId);
        if (s.getStatus() == SampleStatus.APPROVED) {
            return withFiles(s);
        }
        if (s.getStatus() != SampleStatus.SUBMITTED) {
            throw refused(s, "approved", "SUBMITTED");
        }
        List<SampleFile> fileRows = files.findBySampleIdOrderByIdAsc(sampleId);
        Map<String, Object> before = SampleService.snapshot(s, fileRows);
        s.setStatus(SampleStatus.APPROVED);
        s = samples.saveAndFlush(s);
        int granted = incentives.earnForApprovedSample(s);
        Map<String, Object> after = SampleService.snapshot(s, fileRows);
        after.put("grantedUnits", granted);
        audit.record(actor, ACTION_APPROVED, SampleService.OBJECT_SAMPLE, s.getId().toString(), before, after);
        return new SampleWithFiles(s, fileRows);
    }

    /** {@code reason} must already be validated (non-blank, trimmed, at most 500 chars). */
    @Transactional
    public SampleWithFiles returnSample(long sampleId, String reason, String actor) {
        Sample s = lock(sampleId);
        if (s.getStatus() == SampleStatus.RETURNED) {
            return withFiles(s);
        }
        if (s.getStatus() != SampleStatus.SUBMITTED) {
            throw refused(s, "returned", "SUBMITTED");
        }
        List<SampleFile> fileRows = files.findBySampleIdOrderByIdAsc(sampleId);
        Map<String, Object> before = SampleService.snapshot(s, fileRows);
        s.setStatus(SampleStatus.RETURNED);
        s.setReturnReason(reason);
        s = samples.saveAndFlush(s);
        audit.record(actor, ACTION_RETURNED, SampleService.OBJECT_SAMPLE, s.getId().toString(), before,
                SampleService.snapshot(s, fileRows));
        return new SampleWithFiles(s, fileRows);
    }

    @Transactional
    public SampleWithFiles voidSample(long sampleId, String actor) {
        Sample s = lock(sampleId);
        if (s.getStatus() == SampleStatus.VOIDED) {
            return withFiles(s);
        }
        if (!EnumSet.of(SampleStatus.SUBMITTED, SampleStatus.RETURNED, SampleStatus.APPROVED)
                .contains(s.getStatus())) {
            throw refused(s, "voided", "SUBMITTED, RETURNED or APPROVED");
        }
        List<SampleFile> fileRows = files.findBySampleIdOrderByIdAsc(sampleId);
        Map<String, Object> before = SampleService.snapshot(s, fileRows);
        s.setStatus(SampleStatus.VOIDED);
        s = samples.saveAndFlush(s);
        IncentiveService.Clawback clawback = incentives.clawbackForVoidedSample(s);
        Map<String, Object> after = SampleService.snapshot(s, fileRows);
        after.put("earnedUnits", clawback.earned());
        after.put("clawedBackUnits", clawback.clawedBack());
        audit.record(actor, ACTION_VOIDED, SampleService.OBJECT_SAMPLE, s.getId().toString(), before, after);
        return new SampleWithFiles(s, fileRows);
    }

    private Sample lock(long sampleId) {
        return samples.findForUpdate(sampleId).orElseThrow(() -> new SampleNotFoundException(sampleId));
    }

    private SampleWithFiles withFiles(Sample s) {
        return new SampleWithFiles(s, files.findBySampleIdOrderByIdAsc(s.getId()));
    }

    private static SampleStateException refused(Sample s, String verb, String from) {
        return new SampleStateException("sample " + s.getId() + " is " + s.getStatus()
                + "; only " + from + " samples can be " + verb);
    }
}

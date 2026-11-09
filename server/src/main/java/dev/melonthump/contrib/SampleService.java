package dev.melonthump.contrib;

import dev.melonthump.contrib.ContributionService.ContributorNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Contributor sample submission and self-service (design doc 2.0 §2
 * item 8, §5 items 1 + 6, §7 items 7, 8, 10).
 *
 * <ul>
 *   <li>submit: APPROVED contributors only; creates a SUBMITTED sample
 *       from whatever parts arrived (incomplete is allowed).</li>
 *   <li>append: the owner adds parts while SUBMITTED or RETURNED; a
 *       RETURNED sample goes back to SUBMITTED with the reason cleared.
 *       A new recording / cut-open photo replaces the existing one,
 *       new appearance photos are added, new feedback overwrites.</li>
 *   <li>withdraw: the owner deletes a SUBMITTED or RETURNED sample —
 *       rows removed, files deleted from disk right after commit; the
 *       audit row is the surviving record (§7 item 8 true deletion).</li>
 * </ul>
 * Every change writes an audit row (actor = contributor id) in the same
 * transaction. Samples that do not exist and samples of another
 * contributor are indistinguishable to the caller
 * ({@link SampleForbiddenException} for both).
 */
@Service
public class SampleService {

    public static final String OBJECT_SAMPLE = "SAMPLE";
    public static final String ACTION_SUBMITTED = "SAMPLE_SUBMITTED";
    public static final String ACTION_APPENDED = "SAMPLE_APPENDED";
    public static final String ACTION_RESUBMITTED = "SAMPLE_RESUBMITTED";
    public static final String ACTION_WITHDRAWN = "SAMPLE_WITHDRAWN";

    private static final Set<SampleStatus> OPEN_STATES = EnumSet.of(SampleStatus.SUBMITTED, SampleStatus.RETURNED);

    private final ContributorRepository contributors;
    private final SampleRepository samples;
    private final SampleFileRepository files;
    private final MaterialStorage storage;
    private final AuditLogService audit;

    public SampleService(ContributorRepository contributors, SampleRepository samples, SampleFileRepository files,
                         MaterialStorage storage, AuditLogService audit) {
        this.contributors = contributors;
        this.samples = samples;
        this.files = files;
        this.storage = storage;
        this.audit = audit;
    }

    // ---- inputs / outputs ----------------------------------------------------

    /** Opens the bytes of one uploaded file (may be called more than once). */
    @FunctionalInterface
    public interface Source {
        InputStream open() throws IOException;
    }

    /** One validated uploaded file: part, normalized content type, declared size. */
    public record Upload(SamplePart part, String contentType, long sizeBytes, Source source) {
    }

    /** Validated feedback: the fourth part. */
    public record Feedback(int score, List<TasteTag> tasteTags, BandTruth bandTruth) {
    }

    /**
     * FIX12: the client's on-device Vision scores (0-1); each null when
     * not sent. Advisory annotation only. {@code watermelon} is FIX12's
     * legacy combined score; FIX12B adds the per-kind whole / rind scores.
     */
    public record Vision(Double watermelon, Double cutOpenWatermelon, Double wholeWatermelon,
                         Double rindWatermelon) {
        public static final Vision NONE = new Vision(null, null, null, null);
    }

    /** Validated submission metadata (the melon record bookkeeping fields). */
    public record Meta(UUID contributorId, Variety variety, Integer weightGrams, WeightProvenance weightProvenance,
                       String source, LocalDate melonDate, Feedback feedback, Vision vision) {
    }

    /** A sample together with its material file rows. */
    public record SampleWithFiles(Sample sample, List<SampleFile> files) {
    }

    public static final class ContributorNotApprovedException extends RuntimeException {
        public ContributorNotApprovedException(UUID id, ContributorStatus status) {
            super("contributor " + id + " is " + status + ", not APPROVED");
        }
    }

    /** Unknown sample or a sample of another contributor (deliberately not told apart). */
    public static final class SampleForbiddenException extends RuntimeException {
        public SampleForbiddenException(long sampleId) {
            super("sample " + sampleId + " is not accessible to this contributor");
        }
    }

    public static final class SampleStateException extends RuntimeException {
        public SampleStateException(String message) {
            super(message);
        }
    }

    /** Request content that is only invalid against the stored sample (e.g. too many photos). */
    public static final class InvalidSampleException extends RuntimeException {
        public InvalidSampleException(String message) {
            super(message);
        }
    }

    // ---- commands ------------------------------------------------------------

    @Transactional
    public SampleWithFiles submit(Meta meta, List<Upload> uploads) {
        requireApproved(meta.contributorId());
        checkCounts(0, uploads);
        Sample sample = new Sample(meta.contributorId(), meta.variety());
        sample.setWeight(meta.weightGrams(), meta.weightProvenance());
        sample.setSource(meta.source());
        sample.setMelonDate(meta.melonDate());
        applyFeedback(sample, meta.feedback());
        applyVision(sample, meta.vision());
        sample = samples.saveAndFlush(sample);

        List<SampleFile> stored = new ArrayList<>();
        for (Upload u : uploads) {
            stored.add(storeFile(sample, u));
        }
        recomputeParts(sample, stored);
        sample = samples.saveAndFlush(sample);
        audit.record(meta.contributorId().toString(), ACTION_SUBMITTED, OBJECT_SAMPLE, sample.getId().toString(),
                null, snapshot(sample, stored));
        return new SampleWithFiles(sample, stored);
    }

    @Transactional
    public SampleWithFiles append(long sampleId, UUID contributorId, Feedback feedback, List<Upload> uploads) {
        return append(sampleId, contributorId, feedback, Vision.NONE, uploads);
    }

    /** As {@link #append(long, UUID, Feedback, List)}; a sent vision score overwrites, an absent one is kept. */
    @Transactional
    public SampleWithFiles append(long sampleId, UUID contributorId, Feedback feedback, Vision vision,
                                  List<Upload> uploads) {
        Contributor contributor = requireContributor(contributorId);
        Sample sample = ownedForUpdate(sampleId, contributorId);
        if (contributor.getStatus() != ContributorStatus.APPROVED) {
            throw new ContributorNotApprovedException(contributorId, contributor.getStatus());
        }
        if (!OPEN_STATES.contains(sample.getStatus())) {
            throw new SampleStateException("sample " + sampleId + " is " + sample.getStatus()
                    + "; parts can only be appended while SUBMITTED or RETURNED");
        }
        List<SampleFile> current = new ArrayList<>(files.findBySampleIdOrderByIdAsc(sampleId));
        Map<String, Object> before = snapshot(sample, current);

        // A new recording / cut-open photo replaces the existing one.
        List<String> replaced = new ArrayList<>();
        for (SamplePart single : EnumSet.of(SamplePart.RECORDING, SamplePart.CUT_OPEN)) {
            if (uploads.stream().anyMatch(u -> u.part() == single)) {
                for (SampleFile old : List.copyOf(current)) {
                    if (old.getPart() == single) {
                        files.delete(old);
                        current.remove(old);
                        replaced.add(old.getStoredPath());
                    }
                }
            }
        }
        long existingAppearance = current.stream().filter(f -> f.getPart() == SamplePart.APPEARANCE).count();
        checkCounts(existingAppearance, uploads);
        files.flush();
        if (!replaced.isEmpty()) {
            storage.deleteAfterCommit(replaced, null);
        }
        for (Upload u : uploads) {
            current.add(storeFile(sample, u));
        }
        if (feedback != null) {
            applyFeedback(sample, feedback);
        }
        applyVision(sample, vision);
        recomputeParts(sample, current);

        String action = ACTION_APPENDED;
        if (sample.getStatus() == SampleStatus.RETURNED) {
            sample.setStatus(SampleStatus.SUBMITTED);
            sample.setReturnReason(null);
            action = ACTION_RESUBMITTED;
        }
        sample.touch();
        sample = samples.saveAndFlush(sample);
        audit.record(contributorId.toString(), action, OBJECT_SAMPLE, sample.getId().toString(),
                before, snapshot(sample, current));
        return new SampleWithFiles(sample, current);
    }

    @Transactional
    public void withdraw(long sampleId, UUID contributorId) {
        requireContributor(contributorId);
        Sample sample = ownedForUpdate(sampleId, contributorId);
        if (!OPEN_STATES.contains(sample.getStatus())) {
            throw new SampleStateException("sample " + sampleId + " is " + sample.getStatus()
                    + "; only SUBMITTED or RETURNED samples can be withdrawn");
        }
        List<SampleFile> current = files.findBySampleIdOrderByIdAsc(sampleId);
        Map<String, Object> before = snapshot(sample, current);
        List<String> paths = new ArrayList<>();
        for (SampleFile f : current) {
            paths.add(f.getStoredPath());
            files.delete(f);
        }
        files.flush();
        samples.delete(sample);
        samples.flush();
        audit.record(contributorId.toString(), ACTION_WITHDRAWN, OBJECT_SAMPLE, Long.toString(sampleId),
                before, null);
        storage.deleteAfterCommit(paths, storage.sampleDir(contributorId, sampleId));
    }

    // ---- queries -------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Sample> list(UUID contributorId) {
        requireContributor(contributorId);
        return samples.findByContributorIdOrderByCreatedAtDescIdDesc(contributorId);
    }

    @Transactional(readOnly = true)
    public SampleWithFiles get(long sampleId, UUID contributorId) {
        requireContributor(contributorId);
        Sample sample = samples.findById(sampleId)
                .filter(s -> s.getContributorId().equals(contributorId))
                .orElseThrow(() -> new SampleForbiddenException(sampleId));
        return new SampleWithFiles(sample, files.findBySampleIdOrderByIdAsc(sampleId));
    }

    // ---- helpers -------------------------------------------------------------

    private Contributor requireContributor(UUID contributorId) {
        return contributors.findById(contributorId)
                .orElseThrow(() -> new ContributorNotFoundException(contributorId));
    }

    private void requireApproved(UUID contributorId) {
        Contributor c = requireContributor(contributorId);
        if (c.getStatus() != ContributorStatus.APPROVED) {
            throw new ContributorNotApprovedException(contributorId, c.getStatus());
        }
    }

    private Sample ownedForUpdate(long sampleId, UUID contributorId) {
        return samples.findForUpdate(sampleId)
                .filter(s -> s.getContributorId().equals(contributorId))
                .orElseThrow(() -> new SampleForbiddenException(sampleId));
    }

    private static void applyVision(Sample sample, Vision vision) {
        if (vision == null) {
            return;
        }
        if (vision.watermelon() != null) {
            sample.setVisionWatermelon(vision.watermelon());
        }
        if (vision.cutOpenWatermelon() != null) {
            sample.setVisionCutopenWatermelon(vision.cutOpenWatermelon());
        }
        if (vision.wholeWatermelon() != null) {
            sample.setVisionWholeWatermelon(vision.wholeWatermelon());
        }
        if (vision.rindWatermelon() != null) {
            sample.setVisionRindWatermelon(vision.rindWatermelon());
        }
    }

    private static void checkCounts(long existingAppearance, List<Upload> uploads) {
        long appearance = uploads.stream().filter(u -> u.part() == SamplePart.APPEARANCE).count();
        if (existingAppearance + appearance > MaterialRules.MAX_APPEARANCE_PHOTOS) {
            throw new InvalidSampleException("at most " + MaterialRules.MAX_APPEARANCE_PHOTOS
                    + " appearance photos per sample");
        }
    }

    private SampleFile storeFile(Sample sample, Upload u) {
        MaterialStorage.StoredFile stored;
        try (InputStream in = u.source().open()) {
            stored = storage.store(sample.getContributorId(), sample.getId(), u.part(),
                    MaterialRules.extension(u.part(), u.contentType()), in);
        } catch (IOException e) {
            throw new UncheckedIOException("cannot read uploaded part", e);
        }
        return files.save(new SampleFile(sample.getId(), u.part(), stored.sha256(), stored.sizeBytes(),
                u.contentType(), stored.relativePath()));
    }

    private static void applyFeedback(Sample sample, Feedback feedback) {
        if (feedback == null) {
            return;
        }
        sample.setScore(feedback.score());
        sample.setTasteTags(feedback.tasteTags().stream().map(Enum::name).toList());
        sample.setBandTruth(feedback.bandTruth());
    }

    private static void recomputeParts(Sample sample, List<SampleFile> current) {
        boolean appearance = current.stream().anyMatch(f -> f.getPart() == SamplePart.APPEARANCE);
        boolean recording = current.stream().anyMatch(f -> f.getPart() == SamplePart.RECORDING);
        boolean cutOpen = current.stream().anyMatch(f -> f.getPart() == SamplePart.CUT_OPEN);
        boolean feedback = sample.getScore() != null && sample.getBandTruth() != null;
        sample.setParts(appearance, recording, cutOpen, feedback);
    }

    static Map<String, Object> snapshot(Sample s, List<SampleFile> fileRows) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", s.getId());
        m.put("contributorId", s.getContributorId().toString());
        m.put("status", s.getStatus().name());
        m.put("returnReason", s.getReturnReason());
        m.put("variety", s.getVariety().name());
        m.put("weightGrams", s.getWeightGrams());
        m.put("weightProvenance", s.getWeightProvenance() == null ? null : s.getWeightProvenance().name());
        m.put("source", s.getSource());
        m.put("melonDate", s.getMelonDate() == null ? null : s.getMelonDate().toString());
        m.put("hasAppearance", s.hasAppearance());
        m.put("hasRecording", s.hasRecording());
        m.put("hasCutOpen", s.hasCutOpen());
        m.put("hasFeedback", s.hasFeedback());
        m.put("complete", s.isComplete());
        m.put("score", s.getScore());
        m.put("tasteTags", s.getTasteTags());
        m.put("bandTruth", s.getBandTruth() == null ? null : s.getBandTruth().name());
        List<Map<String, Object>> fl = new ArrayList<>();
        for (SampleFile f : fileRows) {
            Map<String, Object> fm = new LinkedHashMap<>();
            fm.put("part", f.getPart().name());
            fm.put("sha256", f.getSha256());
            fm.put("sizeBytes", f.getSizeBytes());
            fm.put("contentType", f.getContentType());
            fl.add(fm);
        }
        m.put("files", fl);
        return m;
    }
}

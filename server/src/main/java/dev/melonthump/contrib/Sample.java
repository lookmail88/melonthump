package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * A contributed sample: the server mirror of one melon record (design
 * doc 2.0 §2 item 8, §7 items 3/7/8/10). {@code complete} is derived
 * from the four part flags on every write (and the schema CHECK enforces
 * the same). Owner-side removal is void-marking
 * ({@link SampleStatus#VOIDED}); the only physical delete is the
 * contributor's own withdrawal of a not-yet-approved sample
 * ({@link SampleService#withdraw}).
 */
@Entity
@Table(name = "samples")
public class Sample {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "contributor_id", nullable = false, updatable = false)
    private UUID contributorId;

    @Enumerated(EnumType.STRING)
    @Column(name = "variety", nullable = false, length = 16)
    private Variety variety;

    @Column(name = "weight_grams")
    private Integer weightGrams;

    @Enumerated(EnumType.STRING)
    @Column(name = "weight_provenance", length = 16)
    private WeightProvenance weightProvenance;

    @Column(name = "source", length = 64)
    private String source;

    @Column(name = "melon_date")
    private LocalDate melonDate;

    @Column(name = "has_appearance", nullable = false)
    private boolean hasAppearance;

    @Column(name = "has_recording", nullable = false)
    private boolean hasRecording;

    @Column(name = "has_cut_open", nullable = false)
    private boolean hasCutOpen;

    @Column(name = "has_feedback", nullable = false)
    private boolean hasFeedback;

    @Column(name = "complete", nullable = false)
    private boolean complete;

    @Column(name = "score")
    private Integer score;

    @Convert(converter = StringListJsonConverter.class)
    @Column(name = "taste_tags")
    private List<String> tasteTags;

    @Enumerated(EnumType.STRING)
    @Column(name = "band_truth", length = 16)
    private BandTruth bandTruth;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private SampleStatus status;

    @Column(name = "return_reason")
    private String returnReason;

    // S4: Pepper's preliminary review (§7 item 10). Admin-side only; written
    // through SampleRepository#setPreliminaryReview, never by entity updates.
    @Enumerated(EnumType.STRING)
    @Column(name = "pepper_recommendation", length = 16, insertable = false, updatable = false)
    private PepperRecommendation pepperRecommendation;

    @Column(name = "pepper_note", insertable = false, updatable = false)
    private String pepperNote;

    @Column(name = "pepper_reviewed_at", insertable = false, updatable = false)
    private Instant pepperReviewedAt;

    // FIX12: on-device Vision `watermelon` confidence (0-1) sent by the
    // client; advisory, null when the client had no score.
    @Column(name = "vision_watermelon")
    private Double visionWatermelon;

    @Column(name = "vision_cutopen_watermelon")
    private Double visionCutopenWatermelon;

    // FIX12B: per-kind scores (best whole-melon photo, best rind close-up).
    @Column(name = "vision_whole_watermelon")
    private Double visionWholeWatermelon;

    @Column(name = "vision_rind_watermelon")
    private Double visionRindWatermelon;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected Sample() {
    }

    public Sample(UUID contributorId, Variety variety) {
        this.contributorId = contributorId;
        this.variety = variety;
        this.status = SampleStatus.SUBMITTED;
    }

    /** All four parts present: appearance, recording, cut-open photo, feedback. */
    public static boolean isComplete(boolean appearance, boolean recording, boolean cutOpen, boolean feedback) {
        return appearance && recording && cutOpen && feedback;
    }

    @PrePersist
    void onCreate() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
        complete = isComplete(hasAppearance, hasRecording, hasCutOpen, hasFeedback);
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
        complete = isComplete(hasAppearance, hasRecording, hasCutOpen, hasFeedback);
    }

    public void setParts(boolean appearance, boolean recording, boolean cutOpen, boolean feedback) {
        this.hasAppearance = appearance;
        this.hasRecording = recording;
        this.hasCutOpen = cutOpen;
        this.hasFeedback = feedback;
        this.complete = isComplete(appearance, recording, cutOpen, feedback);
    }

    /** Marks the row changed (an append that only adds files leaves no other field dirty). */
    public void touch() {
        this.updatedAt = Instant.now();
    }

    public void setScore(Integer score) {
        if (score != null && (score < 0 || score > 100)) {
            throw new IllegalArgumentException("score must be 0-100");
        }
        this.score = score;
    }

    public void setWeight(Integer weightGrams, WeightProvenance provenance) {
        if (weightGrams != null && weightGrams <= 0) {
            throw new IllegalArgumentException("weightGrams must be positive");
        }
        this.weightGrams = weightGrams;
        this.weightProvenance = provenance;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public void setMelonDate(LocalDate melonDate) {
        this.melonDate = melonDate;
    }

    public void setTasteTags(List<String> tasteTags) {
        this.tasteTags = tasteTags == null ? null : List.copyOf(tasteTags);
    }

    public void setBandTruth(BandTruth bandTruth) {
        this.bandTruth = bandTruth;
    }

    public void setStatus(SampleStatus status) {
        this.status = status;
    }

    public void setReturnReason(String returnReason) {
        this.returnReason = returnReason;
    }

    public Double getVisionWatermelon() {
        return visionWatermelon;
    }

    public void setVisionWatermelon(Double visionWatermelon) {
        this.visionWatermelon = visionWatermelon;
    }

    public Double getVisionCutopenWatermelon() {
        return visionCutopenWatermelon;
    }

    public void setVisionCutopenWatermelon(Double visionCutopenWatermelon) {
        this.visionCutopenWatermelon = visionCutopenWatermelon;
    }

    public Double getVisionWholeWatermelon() {
        return visionWholeWatermelon;
    }

    public void setVisionWholeWatermelon(Double visionWholeWatermelon) {
        this.visionWholeWatermelon = visionWholeWatermelon;
    }

    public Double getVisionRindWatermelon() {
        return visionRindWatermelon;
    }

    public void setVisionRindWatermelon(Double visionRindWatermelon) {
        this.visionRindWatermelon = visionRindWatermelon;
    }

    public Long getId() {
        return id;
    }

    public UUID getContributorId() {
        return contributorId;
    }

    public Variety getVariety() {
        return variety;
    }

    public Integer getWeightGrams() {
        return weightGrams;
    }

    public WeightProvenance getWeightProvenance() {
        return weightProvenance;
    }

    public String getSource() {
        return source;
    }

    public LocalDate getMelonDate() {
        return melonDate;
    }

    public boolean hasAppearance() {
        return hasAppearance;
    }

    public boolean hasRecording() {
        return hasRecording;
    }

    public boolean hasCutOpen() {
        return hasCutOpen;
    }

    public boolean hasFeedback() {
        return hasFeedback;
    }

    public boolean isComplete() {
        return complete;
    }

    public Integer getScore() {
        return score;
    }

    public List<String> getTasteTags() {
        return tasteTags;
    }

    public BandTruth getBandTruth() {
        return bandTruth;
    }

    public SampleStatus getStatus() {
        return status;
    }

    public String getReturnReason() {
        return returnReason;
    }

    public PepperRecommendation getPepperRecommendation() {
        return pepperRecommendation;
    }

    public String getPepperNote() {
        return pepperNote;
    }

    public Instant getPepperReviewedAt() {
        return pepperReviewedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}

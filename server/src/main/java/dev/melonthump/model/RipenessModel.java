package dev.melonthump.model;

import dev.melonthump.audio.AudioFeatures;

/**
 * Pluggable ripeness classifier.
 *
 * <p>v1 ships with {@link HeuristicRipenessModel} (fixed thresholds). A future
 * ML-backed implementation (e.g. trained on labeled tap recordings) can replace
 * it without touching the API layer — just register another bean.
 */
public interface RipenessModel {

    /** Version string reported in API responses, e.g. {@code "heuristic-v1"}. */
    String modelVersion();

    RipenessResult classify(AudioFeatures features);
}

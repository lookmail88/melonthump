package dev.melonthump.model;

import dev.melonthump.audio.AudioFeatures;
import org.springframework.stereotype.Component;

/**
 * v1 fixed-threshold classifier.
 *
 * <p><b>PLACEHOLDER thresholds.</b> These values are educated guesses from folk
 * acoustics, not calibrated measurements:
 * <ul>
 *   <li>ripe watermelon tap → deep, hollow resonance (lower dominant frequency)</li>
 *   <li>unripe tap → higher-pitched "ping"</li>
 *   <li>overripe tap → very dull, short thud</li>
 * </ul>
 * They MUST be re-calibrated once labeled data (tap recording + cut-open
 * ground truth) is collected. See the roadmap in the root README.
 */
@Component
public class HeuristicRipenessModel implements RipenessModel {

    /** Below this dominant frequency (Hz) the melon reads as overripe. */
    static final double OVERRIPE_MAX_HZ = 160.0;
    /** Below this dominant frequency (Hz) the melon reads as ripe. */
    static final double RIPE_MAX_HZ = 280.0;

    @Override
    public String modelVersion() {
        return "heuristic-v1";
    }

    @Override
    public RipenessResult classify(AudioFeatures features) {
        double f = features.dominantFrequencyHz();
        if (f < OVERRIPE_MAX_HZ) {
            return new RipenessResult(RipenessVerdict.OVERRIPE, confidence(f, OVERRIPE_MAX_HZ));
        }
        if (f < RIPE_MAX_HZ) {
            double distToEdge = Math.min(f - OVERRIPE_MAX_HZ, RIPE_MAX_HZ - f);
            return new RipenessResult(RipenessVerdict.RIPE, confidence(distToEdge, (RIPE_MAX_HZ - OVERRIPE_MAX_HZ) / 2));
        }
        return new RipenessResult(RipenessVerdict.UNRIPE, confidence(f - RIPE_MAX_HZ, 120.0));
    }

    /**
     * Maps distance-to-decision-boundary to a confidence in [0.55, 0.95].
     * Far from the boundary → more confident. Never 1.0: v1 is a heuristic.
     */
    private static double confidence(double distanceHz, double scaleHz) {
        double c = 0.55 + 0.40 * Math.min(1.0, distanceHz / scaleHz);
        return Math.min(0.95, c);
    }
}

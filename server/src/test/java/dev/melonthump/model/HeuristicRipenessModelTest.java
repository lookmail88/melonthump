package dev.melonthump.model;

import static org.assertj.core.api.Assertions.assertThat;

import dev.melonthump.audio.AudioFeatures;
import org.junit.jupiter.api.Test;

class HeuristicRipenessModelTest {

    private final HeuristicRipenessModel model = new HeuristicRipenessModel();

    private static AudioFeatures features(double dominantHz) {
        return new AudioFeatures(dominantHz, dominantHz * 2, 150.0, 1000.0, 16000);
    }

    @Test
    void lowFrequencyReadsOverripe() {
        RipenessResult r = model.classify(features(100.0));
        assertThat(r.verdict()).isEqualTo(RipenessVerdict.OVERRIPE);
    }

    @Test
    void midFrequencyReadsRipe() {
        RipenessResult r = model.classify(features(220.0));
        assertThat(r.verdict()).isEqualTo(RipenessVerdict.RIPE);
    }

    @Test
    void highFrequencyReadsUnripe() {
        RipenessResult r = model.classify(features(450.0));
        assertThat(r.verdict()).isEqualTo(RipenessVerdict.UNRIPE);
    }

    @Test
    void confidenceStaysInRange() {
        for (double f : new double[]{80, 160, 220, 280, 600}) {
            RipenessResult r = model.classify(features(f));
            assertThat(r.confidence()).isBetween(0.0, 1.0);
        }
    }

    @Test
    void versionIsHeuristicV1() {
        assertThat(model.modelVersion()).isEqualTo("heuristic-v1");
    }
}

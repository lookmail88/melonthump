package dev.melonthump.audio;

/**
 * Acoustic features extracted from a watermelon tap recording.
 *
 * @param dominantFrequencyHz strongest resonant frequency (Hz), DC excluded
 * @param spectralCentroidHz  "brightness" of the tap (Hz)
 * @param decayTimeMs         time for the tap envelope to decay to 1/e of its peak (ms)
 * @param durationMs          analyzed audio duration (ms)
 * @param sampleRateHz        sample rate (Hz)
 */
public record AudioFeatures(
        double dominantFrequencyHz,
        double spectralCentroidHz,
        double decayTimeMs,
        double durationMs,
        int sampleRateHz) {
}

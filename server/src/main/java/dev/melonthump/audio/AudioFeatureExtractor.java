package dev.melonthump.audio;

import org.apache.commons.math3.complex.Complex;
import org.apache.commons.math3.transform.DftNormalization;
import org.apache.commons.math3.transform.FastFourierTransformer;
import org.apache.commons.math3.transform.TransformType;
import org.springframework.stereotype.Component;

/**
 * Extracts {@link AudioFeatures} from tap audio using FFT (Apache Commons Math).
 *
 * <p>Pipeline: take up to the first 2 seconds → Hann window → FFT →
 * dominant frequency (argmax magnitude, DC excluded, 50–4000 Hz band) →
 * spectral centroid → decay time from the RMS envelope.
 */
@Component
public class AudioFeatureExtractor {

    private static final double MIN_FREQ_HZ = 50.0;
    private static final double MAX_FREQ_HZ = 4000.0;
    private static final double MAX_ANALYZE_SECONDS = 2.0;

    private final FastFourierTransformer fft =
            new FastFourierTransformer(DftNormalization.STANDARD);

    public AudioFeatures extract(WavReader.WavData wav) {
        double[] samples = wav.samples();
        int sampleRate = wav.sampleRateHz();
        int n = Math.min(samples.length, (int) (MAX_ANALYZE_SECONDS * sampleRate));
        if (n < 256) {
            throw new IllegalArgumentException("audio too short: need >= 256 samples");
        }

        // Next power of two for FFT.
        int size = 1;
        while (size < n) {
            size <<= 1;
        }
        double[] windowed = new double[size];
        for (int i = 0; i < n; i++) {
            double hann = 0.5 * (1 - Math.cos(2 * Math.PI * i / (n - 1)));
            windowed[i] = samples[i] * hann;
        }

        Complex[] spectrum = fft.transform(windowed, TransformType.FORWARD);
        int bins = size / 2;
        double binHz = (double) sampleRate / size;

        double maxMag = 0;
        int maxBin = 0;
        double weightedSum = 0;
        double magSum = 0;
        for (int k = 1; k < bins; k++) {
            double freq = k * binHz;
            if (freq < MIN_FREQ_HZ || freq > MAX_FREQ_HZ) {
                continue;
            }
            double mag = spectrum[k].abs();
            weightedSum += freq * mag;
            magSum += mag;
            if (mag > maxMag) {
                maxMag = mag;
                maxBin = k;
            }
        }
        double dominantHz = maxBin * binHz;
        double centroidHz = magSum > 0 ? weightedSum / magSum : 0;

        double decayMs = decayTimeMs(samples, sampleRate);
        double durationMs = 1000.0 * n / sampleRate;
        return new AudioFeatures(dominantHz, centroidHz, decayMs, durationMs, sampleRate);
    }

    /**
     * Time from the envelope peak until it first drops to 1/e of the peak.
     * Envelope = RMS over 20 ms windows.
     */
    private static double decayTimeMs(double[] samples, int sampleRate) {
        int window = Math.max(16, sampleRate / 50);
        int windows = samples.length / window;
        if (windows < 2) {
            return 0;
        }
        double[] env = new double[windows];
        double peak = 0;
        int peakIdx = 0;
        for (int w = 0; w < windows; w++) {
            double sum = 0;
            for (int i = 0; i < window; i++) {
                double s = samples[w * window + i];
                sum += s * s;
            }
            env[w] = Math.sqrt(sum / window);
            if (env[w] > peak) {
                peak = env[w];
                peakIdx = w;
            }
        }
        if (peak == 0) {
            return 0;
        }
        double target = peak / Math.E;
        for (int w = peakIdx + 1; w < windows; w++) {
            if (env[w] <= target) {
                return 1000.0 * (w - peakIdx) * window / sampleRate;
            }
        }
        return 1000.0 * (windows - 1 - peakIdx) * window / sampleRate;
    }
}

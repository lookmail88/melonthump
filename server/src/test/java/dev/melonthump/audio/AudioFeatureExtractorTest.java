package dev.melonthump.audio;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import dev.melonthump.TestWavs;
import java.io.ByteArrayInputStream;
import org.junit.jupiter.api.Test;

class AudioFeatureExtractorTest {

    private final AudioFeatureExtractor extractor = new AudioFeatureExtractor();

    @Test
    void findsDominantFrequencyOfSineTap() throws Exception {
        byte[] wav = TestWavs.sineTap(440, 16000, 1.0);
        WavReader.WavData data = WavReader.read(new ByteArrayInputStream(wav));
        AudioFeatures f = extractor.extract(data);
        assertThat(f.dominantFrequencyHz()).isCloseTo(440.0, within(15.0));
        assertThat(f.spectralCentroidHz()).isCloseTo(440.0, within(120.0));
        assertThat(f.sampleRateHz()).isEqualTo(16000);
    }

    @Test
    void decayTimeIsPositiveForTap() throws Exception {
        byte[] wav = TestWavs.sineTap(200, 16000, 1.0);
        WavReader.WavData data = WavReader.read(new ByteArrayInputStream(wav));
        AudioFeatures f = extractor.extract(data);
        // exp(-12t): 1/e at ~83ms
        assertThat(f.decayTimeMs()).isGreaterThan(20.0).isLessThan(400.0);
    }

    @Test
    void lowVersusHighTapSeparate() throws Exception {
        AudioFeatures low = extractor.extract(
                WavReader.read(new ByteArrayInputStream(TestWavs.sineTap(180, 16000, 1.0))));
        AudioFeatures high = extractor.extract(
                WavReader.read(new ByteArrayInputStream(TestWavs.sineTap(500, 16000, 1.0))));
        assertThat(low.dominantFrequencyHz()).isLessThan(high.dominantFrequencyHz());
    }
}

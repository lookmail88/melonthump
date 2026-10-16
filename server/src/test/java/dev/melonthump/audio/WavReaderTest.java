package dev.melonthump.audio;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import dev.melonthump.TestWavs;
import java.io.ByteArrayInputStream;
import org.junit.jupiter.api.Test;

class WavReaderTest {

    @Test
    void readsMono16BitPcm() throws Exception {
        byte[] wav = TestWavs.sineTap(440, 16000, 0.5);
        WavReader.WavData data = WavReader.read(new ByteArrayInputStream(wav));
        assertThat(data.sampleRateHz()).isEqualTo(16000);
        assertThat(data.samples()).hasSize(8000);
        assertThat(data.samples()[0]).isCloseTo(0.0, org.assertj.core.api.Assertions.within(0.01));
        double peak = 0;
        for (double s : data.samples()) {
            peak = Math.max(peak, Math.abs(s));
        }
        assertThat(peak).isGreaterThan(0.5);
    }

    @Test
    void rejectsNonWav() {
        byte[] junk = "hello world, this is not a wav file at all.........".getBytes();
        assertThatThrownBy(() -> WavReader.read(new ByteArrayInputStream(junk)))
                .isInstanceOf(java.io.IOException.class);
    }
}

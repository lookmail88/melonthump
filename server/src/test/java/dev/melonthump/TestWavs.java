package dev.melonthump;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Builds minimal 16-bit PCM mono WAV bytes for tests. */
public final class TestWavs {

    private TestWavs() {
    }

    /**
     * Sine tone at {@code freqHz} with exponential decay (like a tap),
     * {@code seconds} long at {@code sampleRate}.
     */
    public static byte[] sineTap(double freqHz, int sampleRate, double seconds) throws IOException {
        int frames = (int) (seconds * sampleRate);
        ByteArrayOutputStream pcm = new ByteArrayOutputStream();
        ByteBuffer sb = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < frames; i++) {
            double t = (double) i / sampleRate;
            double decay = Math.exp(-t * 12.0);
            double s = Math.sin(2 * Math.PI * freqHz * t) * decay * 0.8;
            sb.putShort(0, (short) Math.round(s * 32767));
            pcm.write(sb.array());
        }
        byte[] data = pcm.toByteArray();

        ByteBuffer h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        h.put("RIFF".getBytes());
        h.putInt(36 + data.length);
        h.put("WAVE".getBytes());
        h.put("fmt ".getBytes());
        h.putInt(16);
        h.putShort((short) 1); // PCM
        h.putShort((short) 1); // mono
        h.putInt(sampleRate);
        h.putInt(sampleRate * 2);
        h.putShort((short) 2);
        h.putShort((short) 16);
        h.put("data".getBytes());
        h.putInt(data.length);

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(h.array());
        out.write(data);
        return out.toByteArray();
    }
}

package dev.melonthump.audio;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Minimal WAV reader: 16-bit PCM, mono or stereo (stereo is mixed to mono).
 * Samples are returned normalized to [-1, 1].
 */
public final class WavReader {

    private WavReader() {
    }

    public record WavData(double[] samples, int sampleRateHz) {
    }

    public static WavData read(InputStream in) throws IOException {
        byte[] bytes = in.readAllBytes();
        if (bytes.length < 44 || bytes[0] != 'R' || bytes[1] != 'I'
                || bytes[2] != 'F' || bytes[3] != 'F'
                || bytes[8] != 'W' || bytes[9] != 'A'
                || bytes[10] != 'V' || bytes[11] != 'E') {
            throw new IOException("not a WAV file (missing RIFF/WAVE header)");
        }
        ByteBuffer buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);

        int audioFormat = -1;
        int channels = -1;
        int sampleRate = -1;
        int bitsPerSample = -1;
        int dataStart = -1;
        int dataLen = -1;

        int pos = 12;
        while (pos + 8 <= bytes.length) {
            buf.position(pos);
            String chunkId = new String(bytes, pos, 4, java.nio.charset.StandardCharsets.US_ASCII);
            int chunkSize = buf.getInt(pos + 4);
            if ("fmt ".equals(chunkId)) {
                audioFormat = buf.getShort(pos + 8) & 0xFFFF;
                channels = buf.getShort(pos + 10) & 0xFFFF;
                sampleRate = buf.getInt(pos + 12);
                bitsPerSample = buf.getShort(pos + 22) & 0xFFFF;
            } else if ("data".equals(chunkId)) {
                dataStart = pos + 8;
                dataLen = chunkSize;
                break;
            }
            pos += 8 + chunkSize + (chunkSize % 2);
        }

        if (audioFormat != 1) {
            throw new IOException("only 16-bit PCM WAV is supported (format=" + audioFormat + ")");
        }
        if (bitsPerSample != 16) {
            throw new IOException("only 16-bit WAV is supported (bits=" + bitsPerSample + ")");
        }
        if (channels < 1 || channels > 2 || dataStart < 0 || dataLen <= 0) {
            throw new IOException("unsupported or corrupt WAV file");
        }
        int frames = Math.min(dataLen, bytes.length - dataStart) / (2 * channels);
        double[] samples = new double[frames];
        buf.position(dataStart);
        for (int i = 0; i < frames; i++) {
            double acc = 0;
            for (int c = 0; c < channels; c++) {
                acc += buf.getShort() / 32768.0;
            }
            samples[i] = acc / channels;
        }
        return new WavData(samples, sampleRate);
    }
}

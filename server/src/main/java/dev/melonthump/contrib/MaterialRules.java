package dev.melonthump.contrib;

import java.util.Locale;
import java.util.Map;

/**
 * Accepted material files (design doc 2.0 §5 item 1): which declared
 * content types are plausible for each part, the per-file size limits,
 * and the file extension used on disk. The declared multipart content
 * type is what is checked; the bytes are not sniffed.
 */
public final class MaterialRules {

    /** Photo size limit (appearance and cut-open), per file. */
    public static final long MAX_PHOTO_BYTES = 10L * 1024 * 1024;
    /** Recording size limit. */
    public static final long MAX_RECORDING_BYTES = 25L * 1024 * 1024;
    /** Appearance photos kept per sample (across submit and appends). */
    public static final int MAX_APPEARANCE_PHOTOS = 12;

    private static final Map<String, String> IMAGE_TYPES = Map.of(
            "image/jpeg", "jpg",
            "image/jpg", "jpg",
            "image/pjpeg", "jpg",
            "image/png", "png",
            "image/heic", "heic",
            "image/heif", "heif",
            "image/webp", "webp");

    private static final Map<String, String> AUDIO_TYPES = Map.ofEntries(
            Map.entry("audio/wav", "wav"),
            Map.entry("audio/x-wav", "wav"),
            Map.entry("audio/wave", "wav"),
            Map.entry("audio/vnd.wave", "wav"),
            Map.entry("audio/mp4", "m4a"),
            Map.entry("audio/m4a", "m4a"),
            Map.entry("audio/x-m4a", "m4a"),
            Map.entry("audio/aac", "aac"),
            Map.entry("audio/mpeg", "mp3"),
            Map.entry("audio/x-caf", "caf"),
            Map.entry("audio/caf", "caf"),
            Map.entry("audio/flac", "flac"),
            Map.entry("audio/x-flac", "flac"),
            Map.entry("audio/aiff", "aiff"),
            Map.entry("audio/x-aiff", "aiff"));

    private MaterialRules() {
    }

    /** Media type without parameters, lower-cased; null for null/blank. */
    public static String normalize(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            return null;
        }
        int semi = contentType.indexOf(';');
        String base = semi >= 0 ? contentType.substring(0, semi) : contentType;
        return base.strip().toLowerCase(Locale.ROOT);
    }

    /** Whether the normalized content type is acceptable for {@code part}. */
    public static boolean accepts(SamplePart part, String normalizedType) {
        if (normalizedType == null) {
            return false;
        }
        return part == SamplePart.RECORDING
                ? AUDIO_TYPES.containsKey(normalizedType)
                : IMAGE_TYPES.containsKey(normalizedType);
    }

    public static long maxBytes(SamplePart part) {
        return part == SamplePart.RECORDING ? MAX_RECORDING_BYTES : MAX_PHOTO_BYTES;
    }

    /** File extension for an accepted normalized content type. */
    public static String extension(SamplePart part, String normalizedType) {
        String ext = part == SamplePart.RECORDING ? AUDIO_TYPES.get(normalizedType) : IMAGE_TYPES.get(normalizedType);
        return ext == null ? "bin" : ext;
    }
}

package dev.melonthump.contrib;

/**
 * The file-backed parts of a four-part sample (design doc 2.0 §5 item
 * 1). The fourth part, feedback, is structured data on the sample row.
 */
public enum SamplePart {
    /** Pre-knock appearance photos (rind close-ups, whole melon with card): 1..n images. */
    APPEARANCE,
    /** Multi-knock recording: one audio file. */
    RECORDING,
    /** Photo of the cut flesh: one image. */
    CUT_OPEN;

    /** Lowercase file-name stem, e.g. {@code cut_open}. */
    public String fileStem() {
        return name().toLowerCase(java.util.Locale.ROOT);
    }
}

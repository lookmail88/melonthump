package dev.melonthump.contrib;

/**
 * Server-side preset taste vocabulary for sample feedback (design doc
 * 2.0 §5 item 1, "taste description"). Chosen, never typed; an unknown
 * tag is rejected.
 */
public enum TasteTag {
    CRISP,
    MEALY,
    SANDY,
    JUICY,
    SWEET,
    BLAND
}

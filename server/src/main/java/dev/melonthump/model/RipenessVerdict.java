package dev.melonthump.model;

/** Ripeness verdict for a tapped watermelon. */
public enum RipenessVerdict {
    /** High-pitched "ping": not ready yet. */
    UNRIPE,
    /** Deep hollow "punk": ready to eat. */
    RIPE,
    /** Very dull thud: past its prime. */
    OVERRIPE
}
